defmodule Tuist.Threads.Runners do
  @moduledoc """
  Runners: people's own machines that their threads run on.

  Luft registers a runner for the signed-in person (`register/2`) and
  hands its secret to the daemon on that machine (`luft-runner`). The
  daemon long-polls over HTTPS (`poll/3`) and answers what it claimed
  (`respond/3`). A thread's session calls the runner through `call/4`.

  Every operation is a `thread_runner_requests` row, so the agents node waiting
  for an answer and the web replica holding the runner's poll need not be the
  same process, node or release: claims take rows with `FOR UPDATE SKIP
  LOCKED`, and an answer is a guarded update from `claimed` to `done`. PubSub
  only wakes waiters early; each side also rechecks the table on a short tick,
  so a missed broadcast costs latency, never an answer. The caller deletes its
  row once it has the answer or gives up; `delete_expired/0`, run every minute
  by `Tuist.Threads.RecoveryWorker`, deletes rows left by callers that died.
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Threads.Runner
  alias Tuist.Threads.RunnerRequest

  @pubsub Tuist.PubSub
  @max_runners 20
  @online_seconds 60
  @claim_batch 16
  # PubSub wakes both sides as soon as a request or answer arrives; the tick
  # only bounds the delay when a broadcast is lost, and each tick is a query.
  @tick_ms 5_000
  # How long a claimed request may be missing from the daemon's in-flight list
  # before it is handed out again: long enough for the poll that claimed it to
  # reach the daemon.
  @reclaim_seconds 10
  @platforms ~w(macos linux windows)
  @ops ~w(info read_file write_file list_dir exec screenshot mouse_move click scroll type_text key)

  def online_seconds, do: @online_seconds

  # Registration

  @doc """
  Registers a runner for `user` and returns it with its secret, which is shown
  only now; the server keeps its SHA-256.
  """
  def register(user, attrs) do
    name = attrs |> Map.get("name") |> sanitize_name()
    platform = Map.get(attrs, "platform")

    cond do
      name == "" ->
        {:error, :invalid}

      platform not in @platforms ->
        {:error, :invalid}

      Repo.aggregate(from(r in active(), where: r.user_id == ^user.id), :count) >= @max_runners ->
        {:error, :too_many}

      true ->
        token = "tgr_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

        runner =
          Repo.insert!(%Runner{user_id: user.id, name: name, platform: platform, token_hash: hash(token)})

        {:ok, runner, token}
    end
  end

  def list(user) do
    Repo.all(from r in active(), where: r.user_id == ^user.id, order_by: [asc: r.inserted_at])
  end

  @doc "Revokes one of `user`'s runners: its secret stops working and threads can no longer choose it."
  def revoke(user, id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      {count, _} =
        Repo.update_all(
          from(r in active(), where: r.id == ^id and r.user_id == ^user.id),
          set: [revoked_at: now(), updated_at: now()]
        )

      if count == 1, do: :ok, else: {:error, :not_found}
    end
  end

  @doc "The runner a thread of `user` may run on."
  def usable(user, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Runner{} = runner <- Repo.one(from r in active(), where: r.id == ^id and r.user_id == ^user.id) do
      {:ok, runner}
    else
      _ -> {:error, :runner_not_found}
    end
  end

  @doc "The runner a running thread uses, while it is not revoked and still belongs to the thread's owner."
  def for_thread(%{runner_id: id, owner_id: owner_id}) when is_binary(id) do
    case Repo.one(from r in active(), where: r.id == ^id and r.user_id == ^owner_id) do
      %Runner{} = runner -> {:ok, runner}
      nil -> {:error, :runner_not_found}
    end
  end

  def authenticate("tgr_" <> _ = token) do
    case Repo.one(from r in active(), where: r.token_hash == ^hash(token)) do
      %Runner{} = runner -> {:ok, runner}
      nil -> {:error, :unauthorized}
    end
  end

  def authenticate(_token), do: {:error, :unauthorized}

  def online?(%Runner{last_seen_at: nil}), do: false
  def online?(%Runner{last_seen_at: seen}), do: DateTime.diff(now(), seen) <= @online_seconds

  def serialize(%Runner{} = runner) do
    %{
      id: runner.id,
      name: runner.name,
      platform: runner.platform,
      online: online?(runner),
      last_seen_at: runner.last_seen_at,
      capabilities: public_capabilities(runner.capabilities)
    }
  end

  # The runner's poll

  @doc """
  Records that the runner is online with what it allows, then returns the
  operations waiting for it, waiting up to `wait_ms` for one.

  `info["in_flight"]` lists the requests the daemon is running. A request
  claimed a while ago that it doesn't list never reached it (the poll's
  connection dropped, the machine slept, the daemon restarted), so it goes
  back to `pending` for this poll instead of waiting out its timeout.
  """
  def poll(%Runner{} = runner, info, wait_ms) do
    Repo.update_all(from(r in Runner, where: r.id == ^runner.id),
      set: [last_seen_at: now(), capabilities: capabilities(info), updated_at: now()]
    )

    reclaim(runner.id, in_flight(info))
    Phoenix.PubSub.subscribe(@pubsub, runner_topic(runner.id))

    try do
      await_claim(runner.id, System.monotonic_time(:millisecond) + wait_ms)
    after
      Phoenix.PubSub.unsubscribe(@pubsub, runner_topic(runner.id))
    end
  end

  defp await_claim(runner_id, deadline) do
    case claim(runner_id) do
      [] ->
        left = deadline - System.monotonic_time(:millisecond)

        if left <= 0 do
          []
        else
          receive do
            {:runner_request, ^runner_id} -> :ok
          after
            min(left, @tick_ms) -> :ok
          end

          await_claim(runner_id, deadline)
        end

      requests ->
        requests
    end
  end

  defp claim(runner_id) do
    {:ok, requests} =
      Repo.transaction(fn ->
        rows =
          Repo.all(
            from(q in RunnerRequest,
              where: q.runner_id == ^runner_id and q.status == "pending" and q.expires_at > ^now(),
              order_by: [asc: q.inserted_at],
              limit: @claim_batch,
              lock: "FOR UPDATE SKIP LOCKED"
            ),
            log: false
          )

        ids = Enum.map(rows, & &1.id)

        Repo.update_all(from(q in RunnerRequest, where: q.id in ^ids),
          set: [status: "claimed", claimed_at: now(), updated_at: now()]
        )

        Enum.map(rows, &Map.merge(&1.payload, %{"id" => &1.id, "op" => &1.op}))
      end)

    requests
  end

  defp reclaim(runner_id, in_flight) do
    Repo.update_all(
      from(q in RunnerRequest,
        where:
          q.runner_id == ^runner_id and q.status == "claimed" and
            q.claimed_at < ^DateTime.add(now(), -@reclaim_seconds) and q.id not in ^in_flight
      ),
      [set: [status: "pending", claimed_at: nil, updated_at: now()]],
      log: false
    )
  end

  defp in_flight(%{"in_flight" => ids}) when is_list(ids) do
    ids
    |> Enum.take(1_000)
    |> Enum.flat_map(fn id ->
      case Ecto.UUID.cast(id) do
        {:ok, id} -> [id]
        :error -> []
      end
    end)
  end

  defp in_flight(_info), do: []

  @doc "Deletes requests past their expiry, which only a caller that died leaves behind."
  def delete_expired do
    Repo.delete_all(from(q in RunnerRequest, where: q.expires_at < ^now()), log: false)
    :ok
  end

  @doc "Records the runner's answer to one operation it claimed."
  def respond(%Runner{} = runner, request_id, response) do
    with {:ok, id} <- Ecto.UUID.cast(request_id) do
      response = %{
        "ok" => response["ok"] == true,
        "result" => response["result"],
        "error" => if(is_binary(response["error"]), do: String.slice(response["error"], 0, 2_000))
      }

      {count, _} =
        Repo.update_all(
          from(q in RunnerRequest, where: q.id == ^id and q.runner_id == ^runner.id and q.status == "claimed"),
          [set: [status: "done", response: response, updated_at: now()]],
          log: false
        )

      if count == 1 do
        Phoenix.PubSub.broadcast(@pubsub, request_topic(id), {:runner_response, id})
        :ok
      else
        {:error, :not_found}
      end
    end
  end

  # Threads calling a runner

  @doc """
  Asks the runner to perform `op` and waits up to `timeout_ms` for its answer.
  Returns `{:ok, result}`, `{:error, message}` with the runner's own error, or
  `{:error, :timeout}` when it didn't answer, as when it is offline.
  """
  def call(runner_id, op, payload, timeout_ms) when op in @ops do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    request =
      Repo.insert!(
        %RunnerRequest{
          runner_id: runner_id,
          op: op,
          payload: payload,
          expires_at: DateTime.add(now(), div(timeout_ms, 1000) + 1)
        },
        log: false
      )

    Phoenix.PubSub.subscribe(@pubsub, request_topic(request.id))
    Phoenix.PubSub.broadcast(@pubsub, runner_topic(runner_id), {:runner_request, runner_id})

    try do
      await_response(request.id, deadline)
    after
      Phoenix.PubSub.unsubscribe(@pubsub, request_topic(request.id))
      Repo.delete_all(from(q in RunnerRequest, where: q.id == ^request.id), log: false)
    end
  end

  defp await_response(id, deadline) do
    case Repo.one(from(q in RunnerRequest, where: q.id == ^id and q.status == "done", select: q.response), log: false) do
      %{"ok" => true} = response ->
        {:ok, response["result"]}

      %{} = response ->
        {:error, response["error"] || "The runner could not complete the operation."}

      nil ->
        left = deadline - System.monotonic_time(:millisecond)

        if left <= 0 do
          {:error, :timeout}
        else
          receive do
            {:runner_response, ^id} -> :ok
          after
            min(left, @tick_ms) -> :ok
          end

          await_response(id, deadline)
        end
    end
  end

  # Helpers

  defp active, do: from(r in Runner, where: is_nil(r.revoked_at))

  defp runner_topic(id), do: "thread_runner:#{id}"
  defp request_topic(id), do: "thread_runner_request:#{id}"

  defp hash(token), do: :crypto.hash(:sha256, token)

  defp now, do: DateTime.utc_now(:second)

  # What the daemon reports, kept to known keys and bounded sizes.
  defp capabilities(info) when is_map(info) do
    folders =
      case info["folders"] do
        folders when is_list(folders) -> folders |> Enum.filter(&is_binary/1) |> Enum.take(100)
        _ -> []
      end

    %{
      "folders" => Enum.map(folders, &String.slice(&1, 0, 1_000)),
      "new_project_folder" =>
        if(is_binary(info["new_project_folder"]), do: String.slice(info["new_project_folder"], 0, 1_000)),
      "terminal" => info["terminal"] == true,
      "display" => info["display"] == true,
      "portals" => info["portals"] == true,
      "version" => if(is_binary(info["version"]), do: String.slice(info["version"], 0, 40))
    }
  end

  defp capabilities(_info), do: capabilities(%{})

  defp public_capabilities(capabilities) do
    Map.take(capabilities || %{}, ~w(folders new_project_folder terminal display portals))
  end

  defp sanitize_name(name) when is_binary(name) do
    name |> String.trim() |> String.slice(0, 63)
  end

  defp sanitize_name(_name), do: ""
end
