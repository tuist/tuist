defmodule LuftServer.Threads.Runners do
  @moduledoc """
  Runners: people's own machines that their threads run on.

  Luft registers a runner for the signed-in person (`register/2`) and
  hands its secret to the daemon on that machine (`luft-runner`). The
  daemon long-polls over HTTPS (`poll/3`) and answers what it claimed
  (`respond/3`). A thread's run calls the runner through `call/5`.

  Every operation is a `thread_runner_requests` row, so the agents node waiting
  for an answer and the web replica holding the runner's poll need not be the
  same process, node or release: claims fence each transition with the run,
  execution sessions and runner locks; answers guard `claimed` to `done`. PubSub
  only wakes waiters early; each side also rechecks the table on a short tick,
  so a missed broadcast costs latency, never an answer. The caller deletes its
  row once it has the answer or gives up; `delete_expired/0` deletes rows
  left by callers that died.
  """
  import Ecto.Query

  alias LuftServer.Repo
  alias LuftServer.RunnerCredentials
  alias LuftServer.RunnerCredentials.Binding
  alias LuftServer.Sessions
  alias LuftServer.Sessions.Session
  alias LuftServer.Threads
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.Run
  alias LuftServer.Threads.Runner
  alias LuftServer.Threads.RunnerRequest
  alias LuftServer.Threads.Thread
  alias LuftServer.Tuist.Scope

  @pubsub LuftServer.PubSub
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
  Registers a runner for `session` and returns it with its secret, which is shown
  only now; the server keeps its SHA-256.
  """
  def register(%Session{} = session, attrs) do
    name = attrs |> Map.get("name") |> sanitize_name()
    platform = Map.get(attrs, "platform")

    with {:ok, user_id} <- user_id(session),
         true <- name != "" and platform in @platforms do
      fn ->
        # Serialize registrations across all sessions belonging to this person.
        Repo.query!("SELECT pg_advisory_xact_lock($1)", [user_id], log: false)
        if is_nil(Sessions.get_by_id(session.id)), do: Repo.rollback(:unauthorized)

        if Repo.aggregate(from(r in active(), where: r.user_id == ^user_id), :count) >=
             @max_runners,
           do: Repo.rollback(:too_many)

        token = RunnerCredentials.issue(session)

        runner =
          Repo.insert!(
            %Runner{user_id: user_id, name: name, platform: platform, token_hash: hash(token)},
            log: false
          )

        Repo.insert!(%Binding{runner_id: runner.id, session_id: session.id}, log: false)
        {runner, token}
      end
      |> Repo.transaction()
      |> case do
        {:ok, {runner, token}} -> {:ok, runner, token}
        error -> error
      end
    else
      false -> {:error, :invalid}
      error -> error
    end
  end

  def list(%Session{} = session) do
    case user_id(session) do
      {:ok, user_id} ->
        Repo.all(from r in active(), where: r.user_id == ^user_id, order_by: [asc: r.inserted_at])

      _ ->
        []
    end
  end

  @doc "Revokes one of `user`'s runners: its secret stops working and threads can no longer choose it."
  def revoke(%Session{} = session, id) do
    with {:ok, user_id} <- user_id(session),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {count, _} =
        Repo.update_all(
          from(r in Runner,
            where: r.id == ^id and r.user_id == ^user_id and is_nil(r.revoked_at)
          ),
          set: [revoked_at: now(), updated_at: now()]
        )

      if count == 1, do: :ok, else: {:error, :not_found}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "The runner a thread of `user` may run on."
  def usable(%Session{} = session, account_handle, id) when is_binary(account_handle) do
    with %Session{} = session <- Sessions.get_by_id(session.id),
         {:ok, scope} <- Scope.load(session, account_handle),
         true <- scope.can_create_threads,
         {:ok, id} <- Ecto.UUID.cast(id),
         %Runner{} = runner <-
           Repo.one(from r in active(), where: r.id == ^id and r.user_id == ^scope.user_id) do
      {:ok, runner}
    else
      _ -> {:error, :runner_not_found}
    end
  end

  def usable(_session, _account_handle, _id), do: {:error, :runner_not_found}

  @doc "The runner a running thread uses, while it is not revoked and still belongs to the thread's owner."
  def for_thread(%{
        runner_id: id,
        owner_id: owner_id,
        owner_session_id: session_id,
        account_handle: handle
      }) do
    with %Session{} = session <- Sessions.get_by_id(session_id),
         {:ok, ^owner_id} <- user_id(session) do
      usable(session, handle, id)
    else
      _ -> {:error, :runner_not_found}
    end
  end

  def for_thread(_thread), do: {:error, :runner_not_found}

  def authenticate("luft_runner_local_" <> _ = token) do
    with {:ok, _session, ^token} <- RunnerCredentials.resolve(token),
         %Runner{} = runner <-
           Repo.one(from(r in active(), where: r.token_hash == ^hash(token)), log: false) do
      {:ok, runner}
    else
      _ -> {:error, :unauthorized}
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
    case Repo.transaction(fn ->
           if is_nil(lock_active(runner.id)), do: Repo.rollback(:unauthorized)

           Repo.update_all(from(r in Runner, where: r.id == ^runner.id),
             set: [last_seen_at: now(), capabilities: capabilities(info), updated_at: now()]
           )

           reclaim(runner.id, in_flight(info))
         end) do
      {:ok, _} ->
        Phoenix.PubSub.subscribe(@pubsub, runner_topic(runner.id))

        try do
          await_claim(runner.id, System.monotonic_time(:millisecond) + wait_ms)
        after
          Phoenix.PubSub.unsubscribe(@pubsub, runner_topic(runner.id))
        end

      {:error, :unauthorized} ->
        []
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
    RunnerRequest
    |> where([q], q.runner_id == ^runner_id and q.status == "pending" and q.expires_at > ^now())
    |> order_by([q], asc: q.inserted_at)
    |> limit(@claim_batch)
    |> Repo.all(log: false)
    |> Enum.flat_map(&claim_request/1)
  end

  defp claim_request(request) do
    run = request.run_id && Repo.get(Run, request.run_id)

    result =
      with %Run{} <- run do
        with_authority(request.runner_id, %{run | attempt: request.run_attempt}, fn _run ->
          {count, _} =
            Repo.update_all(
              from(q in RunnerRequest,
                where: q.id == ^request.id and q.status == "pending" and q.expires_at > ^now()
              ),
              set: [status: "claimed", claimed_at: now(), updated_at: now()]
            )

          if count != 1, do: Repo.rollback(:not_pending)
          Map.merge(request.payload, %{"id" => request.id, "op" => request.op})
        end)
      end

    case result do
      {:ok, wire} ->
        [wire]

      _ ->
        Repo.update_all(
          from(q in RunnerRequest, where: q.id == ^request.id and q.status == "pending"),
          set: [status: "cancelled", updated_at: now()]
        )

        Phoenix.PubSub.broadcast(
          @pubsub,
          request_topic(request.id),
          {:runner_response, request.id}
        )

        []
    end
  end

  defp reclaim(runner_id, in_flight) do
    Repo.update_all(
      from(q in RunnerRequest,
        where:
          q.runner_id == ^runner_id and q.status == "claimed" and
            q.claimed_at < ^DateTime.shift(now(), second: -@reclaim_seconds) and
            q.id not in ^in_flight
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
    case Ecto.UUID.cast(request_id) do
      {:ok, id} ->
        response = %{
          "ok" => response["ok"] == true,
          "result" => response["result"],
          "error" =>
            if(is_binary(response["error"]), do: String.slice(response["error"], 0, 2_000))
        }

        result =
          Repo.transaction(fn ->
            if is_nil(lock_active(runner.id)), do: Repo.rollback(:not_found)

            Repo.update_all(
              from(q in RunnerRequest,
                where:
                  q.id == ^id and q.runner_id == ^runner.id and q.status == "claimed" and
                    q.expires_at > ^now()
              ),
              [set: [status: "done", response: response, updated_at: now()]],
              log: false
            )
          end)

        if match?({:ok, {1, _}}, result) do
          Phoenix.PubSub.broadcast(@pubsub, request_topic(id), {:runner_response, id})
          :ok
        else
          {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end

  # Threads calling a runner

  @doc """
  Asks the runner to perform `op` and waits up to `timeout_ms` for its answer.
  Returns `{:ok, result}`, `{:error, message}` with the runner's own error, or
  `{:error, :timeout}` when it didn't answer, as when it is offline.
  """
  def call(runner_id, run, op, payload, timeout_ms) when op in @ops do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    with {:ok, request} <-
           with_authority(runner_id, run, fn fresh ->
             Repo.insert!(
               %RunnerRequest{
                 runner_id: runner_id,
                 run_id: fresh.id,
                 run_attempt: fresh.attempt,
                 op: op,
                 payload: payload,
                 expires_at: DateTime.shift(now(), second: div(timeout_ms, 1000) + 1)
               },
               log: false
             )
           end) do
      Phoenix.PubSub.subscribe(@pubsub, request_topic(request.id))
      Phoenix.PubSub.broadcast(@pubsub, runner_topic(runner_id), {:runner_request, runner_id})

      try do
        await_response(request.id, deadline)
      after
        Phoenix.PubSub.unsubscribe(@pubsub, request_topic(request.id))
        Repo.delete_all(from(q in RunnerRequest, where: q.id == ^request.id), log: false)
      end
    end
  end

  defp with_authority(runner_id, run, fun) do
    # Refresh before locking sessions; revalidate exact delegations under locks.
    if Threads.owns_run?(run.id, run.attempt) do
      Repo.transaction(fn ->
        bindings =
          Repo.one(
            from r in Run,
              join: t in Thread,
              on: t.id == r.thread_id,
              join: m in Message,
              on: m.id == r.message_id,
              join: b in Binding,
              on: b.runner_id == ^runner_id,
              where: r.id == ^run.id,
              select: %{
                owner: t.owner_session_id,
                author: m.author_session_id,
                runner: b.session_id
              }
          )

        if is_nil(bindings) or Enum.any?(Map.values(bindings), &is_nil/1),
          do: Repo.rollback(:stale_run)

        session_ids = bindings |> Map.values() |> Enum.uniq() |> Enum.sort()

        # Logout locks sessions before nullifying thread/message foreign keys.
        # Include every execution session, not just the runner's registration,
        # without blocking non-key credential refreshes while waiting on a thread.
        sessions =
          Repo.all(
            from s in Session,
              where: s.id in ^session_ids,
              order_by: s.id,
              lock: "FOR KEY SHARE"
          )

        if length(sessions) != length(session_ids), do: Repo.rollback(:stale_run)
        is_nil(lock_active(runner_id)) and Repo.rollback(:runner_not_found)

        thread = Repo.one(from t in Thread, where: t.id == ^run.thread_id, lock: "FOR UPDATE")
        fresh = Repo.one(from r in Run, where: r.id == ^run.id, lock: "FOR UPDATE")

        (not is_nil(thread) and not is_nil(fresh) and fresh.thread_id == thread.id and
           thread.runner_id == runner_id) or Repo.rollback(:runner_not_found)

        message =
          Repo.one(from m in Message, where: m.id == ^fresh.message_id, lock: "FOR UPDATE")

        (thread.owner_session_id == bindings.owner and not is_nil(message) and
           message.author_session_id == bindings.author) or Repo.rollback(:stale_run)

        Threads.owns_run?(run.id, run.attempt) or Repo.rollback(:stale_run)

        # Scope loads can outlast the lease. Lock it only after those requests,
        # so release/takeover cannot race the transition or be blocked by HTTP.
        Repo.one(
          from s in "agent_sessions",
            where: s.id == ^run.thread_id,
            select: s.id,
            lock: "FOR UPDATE"
        )

        result = fun.(fresh)

        Repo.exists?(
          from s in "agent_sessions",
            where:
              s.id == ^run.thread_id and s.epoch == ^run.attempt and is_nil(s.deleted_at) and
                s.lease_expires_at > fragment("clock_timestamp()")
        ) or Repo.rollback(:stale_run)

        Repo.aggregate(
          from(s in Session,
            where: s.id in ^session_ids and s.expires_at > fragment("clock_timestamp()")
          ),
          :count
        ) == length(session_ids) or Repo.rollback(:stale_run)

        result
      end)
    else
      {:error, :stale_run}
    end
  end

  defp await_response(id, deadline) do
    case Repo.one(
           from(q in RunnerRequest,
             where: q.id == ^id and q.status in ["done", "cancelled"],
             select: {q.status, q.response}
           ),
           log: false
         ) do
      {"cancelled", _} ->
        {:error, :stale_run}

      {"done", %{"ok" => true} = response} ->
        {:ok, response["result"]}

      {"done", %{} = response} ->
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

  defp active do
    from r in Runner,
      join: binding in Binding,
      on: binding.runner_id == r.id,
      join: session in Session,
      on: session.id == binding.session_id,
      where: is_nil(r.revoked_at) and session.expires_at > ^now()
  end

  defp lock_active(id) do
    session_id = Repo.one(from b in Binding, where: b.runner_id == ^id, select: b.session_id)

    # Block logout without blocking non-key credential refreshes. Take the
    # session before locking the runner, matching logout's dependent-row order.
    with session_id when is_binary(session_id) <- session_id,
         %Session{} <-
           Repo.one(
             from s in Session,
               where: s.id == ^session_id and s.expires_at > ^now(),
               lock: "FOR KEY SHARE"
           ) do
      # An unrestricted lock would also upgrade the joined session lock,
      # blocking refresh and deadlocking competing session-reference holders.
      Repo.one(
        from(r in active(), where: r.id == ^id, lock: fragment("FOR UPDATE OF ?", r)),
        log: false
      )
    else
      _ -> nil
    end
  end

  defp user_id(%Session{user_sub: sub}) do
    case Integer.parse(sub) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, :unauthorized}
    end
  end

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
        if(is_binary(info["new_project_folder"]),
          do: String.slice(info["new_project_folder"], 0, 1_000)
        ),
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
