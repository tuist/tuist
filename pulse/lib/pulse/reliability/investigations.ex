defmodule Pulse.Reliability.Investigations do
  @moduledoc "Budgeted, single-attempt handoff to an external investigation runtime."
  alias Pulse.Alerting.Canonical
  alias Pulse.QueryRunner
  alias Pulse.Reliability.Repository

  @hour 3_600_000_000_000
  @receipt_horizon 7 * 24 * @hour

  def dispatch(tenant, signal, deadline, config) do
    if is_binary(config[:investigation_url]) and signal["assessment"]["decision"] == "investigate" do
      token = Repository.nonce() <> Repository.nonce()

      with {:ok, run} <- reserve(tenant, signal, token, config) do
        payload = %{
          "version" => 1,
          "tenant" => tenant,
          "run" => Map.delete(run, "token_hash"),
          "signal" => signal,
          "completion_token" => token,
          "completion_path" => "/api/v1/reliability/investigations/#{run["id"]}/complete"
        }

        remaining = deadline - System.monotonic_time(:millisecond)
        result = send_run(payload, config, remaining)

        Repository.transact(tenant, &delivery_result(&1, run["id"], result))
      end
    else
      {:ok, :disabled_or_not_needed}
    end
  end

  defp delivery_result(root, id, result) do
    current = root["investigations"][id]

    if current["status"] == "dispatching" do
      status = if result == :accepted, do: "accepted", else: "delivery_unknown"
      next = put_in(root, ["investigations", id, "status"], status)
      {:ok, Repository.event(next, "investigation", %{"run_id" => id, "status" => status}), status}
    else
      {:ok, root, current["status"]}
    end
  end

  def complete(tenant, id, token, outcome) when is_binary(tenant) and is_binary(id) and is_binary(token) do
    with :ok <- completion_shape(tenant, id, token, outcome) do
      config = Pulse.Reliability.settings()

      QueryRunner.run(tenant, :reliability_callback, fn _ ->
        Repository.transact(tenant, &complete_run(&1, id, Canonical.digest(token), outcome, config))
      end)
    end
  end

  def complete(_, _, _, _), do: {:error, :invalid_arguments}

  defp completion_shape(tenant, id, token, outcome) do
    if byte_size(tenant) in 1..128 and byte_size(id) == 32 and byte_size(token) == 64 and
         outcome in ["completed", "failed"], do: :ok, else: {:error, :invalid_arguments}
  end

  defp complete_run(root, id, hash, outcome, config) do
    with %{"token_hash" => saved} = run <- root["investigations"][id],
         true <- Plug.Crypto.secure_compare(saved, hash) do
      now = max(Repository.now(config), root["clock_ns"])
      finish_run(root, run, id, outcome, now)
    else
      nil -> {:error, :completion_receipt_unavailable}
      _ -> {:error, :unauthorized}
    end
  end

  defp finish_run(root, run, id, outcome, now) do
    cond do
      run["status"] in ["completed", "failed"] and now - (run["completed_at_ns"] || now) >= @receipt_horizon ->
        {:error, :completion_receipt_unavailable}

      run["status"] == outcome ->
        next = put_in(root, ["investigations", id], Map.put_new(run, "completed_at_ns", now))
        {:ok, next, %{"status" => outcome}}

      run["status"] in ["completed", "failed"] ->
        {:error, :completion_conflict}

      true ->
        finished = Map.merge(run, %{"status" => outcome, "completed_at_ns" => now})
        next = put_in(root, ["investigations", id], finished)
        {:ok, Repository.event(next, "investigation", %{"run_id" => id, "status" => outcome}), %{"status" => outcome}}
    end
  end

  defp reserve(tenant, signal, token, config) do
    id = Repository.nonce()
    Repository.transact(tenant, &reserve_run(&1, signal, token, config, id))
  end

  defp reserve_run(root, signal, token, config, id) do
    with {:ok, now} <- Repository.authorize(config, root["clock_ns"]),
         {:ok, current} <- current_signal(root, signal),
         :ok <- admit_run(root, current, now),
         {:ok, root} <-
           Repository.charge(root, now, "investigation", 5_000_000_000, config[:investigation_budget_nano_usd]) do
      run = %{
        "id" => id,
        "signal_id" => signal["id"],
        "signal_revision" => signal["revision"],
        "episode_id" => signal["episode_id"],
        "status" => "dispatching",
        "started_at_ns" => now,
        "deadline_ns" => now + 15 * 60_000_000_000,
        "max_cost_nano_usd" => 5_000_000_000,
        "token_hash" => Canonical.digest(token)
      }

      day = div(now, 86_400_000_000_000)
      starts = if root["investigation_day"] == day, do: root["investigation_starts"] || 0, else: 0

      root =
        root
        |> Map.put("investigations", retained_runs(root["investigations"], now) |> Map.put(id, run))
        |> Map.put("investigation_day", day)
        |> Map.put("investigation_starts", starts + 1)
        |> Map.put("clock_ns", now)
        |> put_in(["signals", signal["id"], "last_investigation_ns"], now)

      {:ok, Repository.event(root, "investigation", %{"run_id" => id, "status" => "dispatching"}), run}
    end
  end

  defp current_signal(root, signal) do
    current = root["signals"][signal["id"]]

    cond do
      current == nil -> {:error, :stale_signal}
      current["revision"] != signal["revision"] -> {:error, :stale_signal}
      current["assessment"]["decision"] != "investigate" -> {:error, :stale_signal}
      true -> {:ok, current}
    end
  end

  defp admit_run(root, current, now) do
    active = Enum.filter(Map.values(root["investigations"]), &(&1["status"] not in ["completed", "failed"]))
    day = div(now, 86_400_000_000_000)
    starts = if root["investigation_day"] == day, do: root["investigation_starts"] || 0, else: 0
    last = current["last_investigation_ns"]

    cond do
      length(active) >= 2 ->
        {:error, :investigation_concurrency_limit}

      starts >= 20 ->
        {:error, :investigation_daily_limit}

      last != nil and now - last < @hour ->
        {:error, :investigation_cooldown}

      Enum.any?(active, &(&1["signal_id"] == current["id"])) ->
        {:error, :investigation_active}

      true ->
        :ok
    end
  end

  defp retained_runs(runs, now) do
    Map.new(runs, fn {id, run} ->
      if run["status"] in ["completed", "failed"],
        do: {id, Map.put_new(run, "completed_at_ns", now)},
        else: {id, run}
    end)
    |> Map.reject(fn {_, run} ->
      run["status"] in ["completed", "failed"] and now - run["completed_at_ns"] >= @receipt_horizon
    end)
  end

  defp send_run(_payload, _config, remaining) when remaining <= 0, do: :unknown

  defp send_run(payload, config, remaining) do
    timeout = min(remaining, 4000)
    headers = [{"authorization", "Bearer " <> config[:investigation_token]}, {"idempotency-key", payload["run"]["id"]}]

    with {:ok, _} <- Repository.authorize(config),
         {:ok, %{status: status}} when status in [200, 202] <-
           Req.post(config[:investigation_url],
             json: payload,
             headers: headers,
             retry: false,
             redirect: false,
             receive_timeout: timeout,
             request_timeout: timeout,
             decode_body: false,
             compressed: false,
             into: fn {:data, _}, pair -> {:halt, pair} end
           ) do
      :accepted
    else
      _ -> :unknown
    end
  end
end
