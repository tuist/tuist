defmodule Pulse.Reliability do
  @moduledoc "Opt-in, bounded cross-signal assessment. Models judge evidence, never execute queries or remediation."
  alias Pulse.Alerting.Canonical
  alias Pulse.Errors.ProjectionCursor
  alias Pulse.ObjectStore
  alias Pulse.QueryRunner
  alias Pulse.Reliability.Investigations
  alias Pulse.Reliability.OpenAI
  alias Pulse.Reliability.Repository
  alias Pulse.Reliability.Windows
  alias Pulse.Runtime

  @minute 60_000_000_000
  @window 5 * @minute
  @snapshot_bytes 4_194_304

  def settings, do: Runtime.get_env(:pulse, __MODULE__, [])

  @doc false
  def window_end(now), do: div(max(0, now - 2 * @minute), @window) * @window

  def step(tenant, opts \\ []) do
    config = Keyword.merge(settings(), opts)

    with true <- config[:enabled] == true,
         {:ok, now} <- Repository.authorize(config) do
      QueryRunner.run(tenant, :alerting, fn deadline -> advance(tenant, now, deadline, config) end)
    else
      false -> {:error, :reliability_disabled}
      error -> error
    end
  end

  def read(kind, tenant, args \\ %{}) when kind in [:signals, :changes, :signal] do
    QueryRunner.run(tenant, :raw, fn _ ->
      with {:ok, root, _} <- Repository.load(tenant),
           {:ok, cursor} <- ProjectionCursor.open(args["cursor"], tenant, "reliability-v1", kind) do
        page(kind, root, tenant, args, cursor)
      end
    end)
  end

  defp advance(tenant, now, deadline, config) do
    finish = window_end(now)

    with {:ok, root, _} <- Repository.load(tenant),
         :pending <- window_status(root, finish),
         {:ok, snapshot} <- snapshot(tenant, root, finish, now, deadline, config) do
      assess_next(tenant, snapshot, deadline, config)
    end
  end

  defp window_status(root, finish) do
    if get_in(root, ["snapshot", "finish_ns"]) == finish and
         map_size(root["assessments"]) == root["snapshot"]["groups"] do
      {:ok, %{"status" => "complete", "window_end_ns" => finish, "groups" => root["snapshot"]["groups"]}}
    else
      :pending
    end
  end

  defp snapshot(_tenant, %{"snapshot" => %{"finish_ns" => finish} = ref}, finish, _now, _deadline, _config),
    do: fetch_snapshot(ref)

  defp snapshot(tenant, root, finish, now, deadline, config) do
    claim = Repository.nonce()

    with {:ok, _} <- Repository.transact(tenant, &claim_scan(&1, finish, claim, config)),
         {:ok, previous} <- previous_snapshot(root),
         {:ok, snapshot} <- Windows.scan(tenant, previous, finish, deadline),
         bytes = Canonical.encode(snapshot),
         true <- byte_size(bytes) <= @snapshot_bytes,
         key = "tenants/#{tenant}/reliability/v1/windows/#{Canonical.digest(bytes)}.json",
         {:ok, _} <- ObjectStore.put(Repository.config(), key, bytes),
         {:ok, _} <-
           Repository.transact(tenant, &publish_snapshot(&1, claim, key, bytes, snapshot)) do
      if root["snapshot"], do: ObjectStore.delete_bounded(Repository.config(), root["snapshot"]["key"])
      {:ok, snapshot}
    else
      {:error, :reliability_scan_pending} = error ->
        error

      error ->
        record_failure(tenant, finish, now, error)
        if error == false, do: {:error, :reliability_snapshot_limit}, else: error
    end
  end

  defp publish_snapshot(current, claim, key, bytes, snapshot) do
    ref = %{
      "key" => key,
      "digest" => Canonical.digest(bytes),
      "finish_ns" => snapshot["finish_ns"],
      "groups" => map_size(snapshot["groups"])
    }

    cond do
      current["snapshot"] == ref ->
        {:ok, current, :ready}

      current["scan_claim"] == claim ->
        next = current |> Map.put("snapshot", ref) |> Map.put("assessments", %{}) |> Map.delete("scan_claim")

        coverage = %{
          "window_end_ns" => snapshot["finish_ns"],
          "status" => "snapshot_ready",
          "previous_window" => current["snapshot"],
          "previous_assessments" => current["assessments"]
        }

        {:ok, Repository.event(next, "coverage", coverage), :ready}

      true ->
        {:error, :reliability_conflict}
    end
  end

  defp claim_scan(root, finish, claim, config) do
    with {:ok, now} <- Repository.authorize(config, root["clock_ns"]),
         true <- (root["scan_finish_ns"] || -1) < finish,
         {:ok, next} <- Repository.charge(root, now, "objects", 3_000_000, object_limit(config)) do
      {:ok, Map.merge(next, %{"scan_finish_ns" => finish, "scan_claim" => claim, "clock_ns" => now}), :claimed}
    else
      false -> {:error, :reliability_scan_pending}
      error -> error
    end
  end

  defp previous_snapshot(%{"snapshot" => ref}), do: fetch_snapshot(ref)
  defp previous_snapshot(_), do: {:ok, nil}

  defp fetch_snapshot(ref) do
    with {:ok, _, bytes} <- ObjectStore.get_bounded(Repository.config(), ref["key"], nil, @snapshot_bytes),
         true <- Canonical.digest(bytes) == ref["digest"],
         {:ok, snapshot} <- Pulse.JSON.decode(bytes) do
      {:ok, snapshot}
    else
      _ -> {:error, :reliability_snapshot_unavailable}
    end
  end

  defp assess_next(tenant, snapshot, deadline, config) do
    finish = snapshot["finish_ns"]

    with {:ok, root, _} <- Repository.load(tenant) do
      candidate =
        snapshot["groups"]
        |> Enum.sort_by(fn {id, _} -> Canonical.hash([finish, id]) end)
        |> Enum.find(fn {id, _} -> not Map.has_key?(root["assessments"], id) end)

      case candidate do
        nil -> {:ok, %{"status" => "complete", "window_end_ns" => finish, "groups" => map_size(snapshot["groups"])}}
        {id, group} -> assess(tenant, id, group, finish, deadline, config)
      end
    end
  end

  defp assess(tenant, id, group, finish, deadline, config) do
    context = %{
      tenant: tenant,
      id: id,
      finish: finish,
      deadline: deadline,
      config: config,
      attempt: Repository.nonce()
    }

    case reserve(context, true) do
      {:ok, _} ->
        input = Map.put(Windows.input(group), "window_end_ns", finish)
        result = decision(input, deadline, config)
        {result, query} = followup(result, group, input, context)

        with {:ok, signal} <- publish(group, result, query, context) do
          handoff(signal, context)
          {:ok, signal}
        end

      {:error, :reliability_budget_exhausted} ->
        defer(tenant, id, finish, config)

      error ->
        error
    end
  end

  defp handoff(signal, context) do
    case Investigations.dispatch(context.tenant, signal, context.deadline, context.config) do
      {:error, reason} ->
        Repository.transact(context.tenant, fn root ->
          change = %{"signal_id" => context.id, "revision" => signal["revision"], "reason" => safe_reason(reason)}
          {:ok, Repository.event(root, "investigation_deferred", change), :deferred}
        end)

      _ ->
        :ok
    end
  end

  defp reserve(context, first), do: Repository.transact(context.tenant, &reserve_assessment(&1, context, first))

  defp reserve_assessment(root, context, first) do
    existing = root["assessments"][context.id]

    cond do
      get_in(root, ["snapshot", "finish_ns"]) != context.finish -> {:error, :reliability_stale_window}
      first and existing != nil -> {:error, :reliability_already_assessed}
      not first and not followup_claim?(existing, context.attempt) -> {:error, :reliability_claim_lost}
      true -> charge_assessment(root, context, first)
    end
  end

  defp followup_claim?(%{"attempt_id" => attempt, "calls" => 1, "status" => "outcome_unknown"}, attempt), do: true
  defp followup_claim?(_, _), do: false

  defp charge_assessment(root, context, first) do
    config = context.config

    with {:ok, now} <- Repository.authorize(config, root["clock_ns"]),
         {:ok, root} <-
           Repository.charge(
             root,
             now,
             "model",
             config[:max_input_tokens] * config[:input_nano_usd_per_token],
             config[:assessment_budget_nano_usd]
           ),
         {:ok, root} <- Repository.charge(root, now, "objects", 50_000, object_limit(config)) do
      claim = %{"attempt_id" => context.attempt, "status" => "outcome_unknown", "calls" => if(first, do: 1, else: 2)}
      next = root |> put_in(["assessments", context.id], claim) |> Map.put("clock_ns", now)
      {:ok, next, context.attempt}
    end
  end

  defp decision(input, deadline, config) do
    remaining = deadline - System.monotonic_time(:millisecond)

    with {:ok, _} <- Repository.authorize(config),
         true <- remaining > 0 do
      provider = Keyword.get(config, :provider, OpenAI)

      opts =
        Keyword.take(config, [:api_key, :base_url, :max_input_tokens]) |> Keyword.put(:timeout_ms, min(remaining, 4000))

      provider.assess(input, opts)
    else
      false -> {:error, :assessment_timeout}
      error -> error
    end
  end

  defp followup({:ok, %{"decision" => decision, "query" => query}}, group, input, context)
       when decision != "expected" and query != "none" do
    with {:ok, evidence} <- Windows.query(group, query),
         {:ok, _} <- reserve(context, false) do
      next =
        decision(
          Map.put(input, "followup", %{"query" => query, "result" => evidence}),
          context.deadline,
          context.config
        )

      {next, query}
    else
      {:error, :reliability_budget_exhausted} -> {{:error, :followup_budget_exhausted}, query}
      _ -> {{:error, :followup_unavailable}, query}
    end
  end

  defp followup(result, _group, _input, _context), do: {result, nil}

  defp publish(group, result, query, context),
    do: Repository.transact(context.tenant, &publish_assessment(&1, group, result, query, context))

  defp publish_assessment(root, group, result, query, %{id: id, finish: finish} = context) do
    cond do
      get_in(root, ["snapshot", "finish_ns"]) != finish or
          get_in(root, ["assessments", id, "attempt_id"]) != context.attempt ->
        {:error, :reliability_stale_window}

      get_in(root, ["assessments", id, "status"]) in ["assessed", "unknown"] ->
        {:ok, root, root["signals"][id]}

      true ->
        old = root["signals"][id]
        now = Repository.now(context.config)
        revision = if old, do: old["revision"] + 1, else: 1
        judgement = assessment(result)
        episode = if old && old["assessment"]["decision"] != "expected", do: old["episode_id"], else: Repository.nonce()

        signal = %{
          "id" => id,
          "service" => group["service"],
          "environment" => group["environment"],
          "revision" => revision,
          "window_end_ns" => finish,
          "indexed_at_ns" => now,
          "evidence" => Windows.input(group),
          "followup_query" => query,
          "followup_evidence" => group["queries"][query],
          "assessment" => judgement,
          "episode_id" => episode,
          "last_investigation_ns" => old && old["last_investigation_ns"]
        }

        signals = Map.put(root["signals"], id, signal)
        root = Map.put(root, "signals", signals)
        root = put_in(root, ["assessments", id, "status"], signal["assessment"]["status"])

        root =
          Repository.event(root, "assessment", %{
            "signal_id" => id,
            "revision" => revision,
            "decision" => signal["assessment"]["decision"],
            "status" => signal["assessment"]["status"],
            "indexed_at_ns" => now
          })

        {:ok, root, signal}
    end
  end

  defp assessment({:ok, answer}), do: Map.put(answer, "status", "assessed")
  defp assessment({:error, reason}), do: %{"status" => "unknown", "reason" => safe_reason(reason), "decision" => nil}

  defp defer(tenant, id, finish, config) do
    Repository.transact(tenant, fn root ->
      cond do
        get_in(root, ["snapshot", "finish_ns"]) != finish ->
          {:error, :reliability_stale_window}

        Map.has_key?(root["assessments"], id) ->
          {:error, :reliability_already_assessed}

        true ->
          next = put_in(root, ["assessments", id], %{"status" => "budget_deferred"})
          change = %{"signal_id" => id, "indexed_at_ns" => Repository.now(config)}
          {:ok, Repository.event(next, "assessment_deferred", change), %{"status" => "budget_deferred"}}
      end
    end)
  end

  defp record_failure(tenant, finish, now, error) do
    Repository.transact(tenant, fn root ->
      if root["failure_finish_ns"] == finish do
        {:error, :already_reported}
      else
        status = %{
          "status" => "unknown",
          "window_end_ns" => finish,
          "indexed_at_ns" => now,
          "reason" => safe_reason(error)
        }

        next = Map.put(root, "failure_finish_ns", finish)
        {:ok, Repository.event(next, "coverage", status), :recorded}
      end
    end)
  end

  defp page(:signal, root, _tenant, %{"id" => id}, nil) do
    case root["signals"][id] do
      nil -> {:error, :not_found}
      signal -> {:ok, signal}
    end
  end

  defp page(kind, root, tenant, args, cursor) when kind in [:signals, :changes] do
    limit = args["limit"] || 20

    if limit in 1..100 and valid_cursor?(cursor, root, kind) do
      {rows, position} = page_rows(kind, root, cursor, limit)

      ref = %{"generation" => root["generation"], "sequence" => root["sequence"]}
      ref = if kind == :changes, do: Map.put(ref, "sequence", position), else: Map.put(ref, "offset", position)

      {:ok,
       %{
         "results" => rows,
         "next_cursor" => if(root["publication"], do: ProjectionCursor.seal(ref, tenant, "reliability-v1", kind)),
         "sequence" => root["sequence"],
         "replay_floor" => root["replay_floor"],
         "spend_nano_usd" => root["spend"],
         "snapshot" => Map.take(root["snapshot"] || %{}, ["finish_ns", "groups"]),
         "capture" => Map.take(root, ["scan_finish_ns", "failure_finish_ns"]),
         "assessments" => root["assessments"],
         "investigations" => Enum.map(Map.values(root["investigations"]), &Map.delete(&1, "token_hash")),
         "coverage" => "observed_snapshot_not_exporter_completeness"
       }}
    else
      {:error, :reset_required}
    end
  end

  defp valid_cursor?(nil, _root, _kind), do: true

  defp valid_cursor?(%{"generation" => generation, "sequence" => sequence} = cursor, root, kind) do
    generation == root["generation"] and valid_position?(kind, root, sequence, cursor["offset"])
  end

  defp valid_cursor?(_, _, _), do: false

  defp valid_position?(:changes, root, sequence, _) do
    is_integer(sequence) and sequence >= root["replay_floor"] and sequence <= root["sequence"]
  end

  defp valid_position?(:signals, root, sequence, offset) do
    sequence == root["sequence"] and is_integer(offset) and offset >= 0 and offset <= map_size(root["signals"])
  end

  defp page_rows(:changes, root, cursor, limit) do
    sequence = if cursor, do: cursor["sequence"], else: root["replay_floor"]
    rows = root["changes"] |> Enum.filter(&(&1["sequence"] > sequence)) |> Enum.take(limit)
    {rows, if(rows == [], do: sequence, else: List.last(rows)["sequence"])}
  end

  defp page_rows(:signals, root, cursor, limit) do
    rows = root["signals"] |> Enum.sort() |> Enum.map(&elem(&1, 1))
    offset = if cursor, do: cursor["offset"], else: 0
    {Enum.slice(rows, offset, limit), offset + min(limit, max(0, length(rows) - offset))}
  end

  defp object_limit(config), do: Keyword.get(config, :object_budget_nano_usd, 100_000_000_000)
  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason({:error, reason}), do: safe_reason(reason)
  defp safe_reason(_), do: "reliability_work_failed"
end
