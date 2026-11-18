defmodule Tuist.Threads do
  @moduledoc """
  Private, durable conversations. PostgreSQL owns history, execution leases,
  tool reservations and Ship approvals; processes and sockets are disposable.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Agents.Lease
  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Push
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Threads.Agent
  alias Tuist.Threads.Approval
  alias Tuist.Threads.Checkout
  alias Tuist.Threads.Message
  alias Tuist.Threads.Provider
  alias Tuist.Threads.Repository
  alias Tuist.Threads.Run
  alias Tuist.Threads.Shipping
  alias Tuist.Threads.Thread
  alias Tuist.Threads.ToolCall
  alias Tuist.Threads.Worker
  alias Tuist.Threads.Workspace

  @active ["queued", "running"]
  # How long an inference run may take across every host it is handed to.
  @run_max_hours 3

  # Threads always need the user's `:guild` flag: they run on the user's own AI
  # subscriptions, which that flag gates. An organization must also opt in with
  # its own flag, as its AI routing does.
  def authorize(%User{active: true, disabled_at: nil} = user, account) when not is_nil(account) do
    enabled? =
      FeatureFlags.guild_enabled?(user) and
        (not Accounts.organization?(account) or FeatureFlags.organization_guild_enabled?(account))

    if enabled? and Authorization.authorize(:account_update, user, account) == :ok,
      do: :ok,
      else: {:error, :forbidden}
  end

  def authorize(_, _), do: {:error, :forbidden}

  def topic(user_id, account_id), do: "threads:#{account_id}:#{user_id}"

  def list(user, account, cursor \\ nil) do
    with :ok <- authorize(user, account),
         {:ok, boundary} <- decode_cursor(cursor) do
      query = from t in Thread, where: t.owner_id == ^user.id and t.account_id == ^account.id

      query =
        if boundary,
          do:
            from(t in query,
              where:
                t.updated_at < ^elem(boundary, 0) or (t.updated_at == ^elem(boundary, 0) and t.id < ^elem(boundary, 1))
            ),
          else: query

      rows = Repo.all(from t in query, order_by: [desc: t.updated_at, desc: t.id], limit: 26)
      page = Enum.take(rows, 25)
      last = List.last(page)

      next =
        if length(rows) > 25,
          do: Base.url_encode64(JSON.encode!([DateTime.to_iso8601(last.updated_at), last.id]), padding: false)

      {:ok, %{threads: page, next_cursor: next}}
    end
  end

  def get(user, account, id, opts \\ []) do
    with :ok <- authorize(user, account),
         {:ok, id} <- uuid(id),
         %Thread{} = thread <- Repo.get_by(Thread, id: id, account_id: account.id, owner_id: user.id),
         {:ok, before} <- before_position(Keyword.get(opts, :before)) do
      {:ok, history(thread, before)}
    else
      nil -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  def repositories(user, account) do
    with :ok <- authorize(user, account), do: Repository.list(account)
  end

  def models(user, account) do
    with :ok <- authorize(user, account), do: {:ok, Provider.models(user)}
  end

  def create(user, account, attrs) do
    provider = attrs["provider"]
    model = attrs["model"]

    with :ok <- authorize(user, account),
         {:ok, request_id} <- uuid(attrs["request_id"]),
         {:ok, body} <- content(attrs["content"]),
         {:ok, repository, branch} <- repository(account, user, attrs),
         hash = fingerprint({body, repository, branch, provider, model}),
         :ok <- creation_model(user, account, request_id, hash, provider, model) do
      fn ->
        # The account row serializes first-use request keys across replicas.
        Repo.one!(from a in Accounts.Account, where: a.id == ^account.id, lock: "FOR UPDATE")
        # Model discovery may refresh credentials and wait on the provider.
        if authorize(Accounts.get_user_by_id(user.id), account) != :ok, do: Repo.rollback(:forbidden)

        case Repo.get_by(Thread, account_id: account.id, owner_id: user.id, request_id: request_id) do
          nil ->
            id = Ecto.UUID.generate()

            thread =
              Repo.insert!(
                %Thread{
                  id: id,
                  account_id: account.id,
                  owner_id: user.id,
                  request_id: request_id,
                  request_hash: hash,
                  goal: body,
                  title: String.slice(body, 0, 80),
                  provider: provider,
                  model: model,
                  repository: repository,
                  base_branch: branch,
                  branch: if(repository, do: "threads/#{id}"),
                  ship_mode: :branch
                },
                log: false
              )

            message = append!(thread, %{kind: "human", body: body, request_id: request_id, author_id: user.id})
            enqueue!(thread, message.id)
            history(Repo.reload!(thread))

          %Thread{request_hash: ^hash} = thread ->
            history(thread)

          _ ->
            Repo.rollback(:request_conflict)
        end
      end
      |> transact()
      |> wake()
    end
  end

  defp creation_model(user, account, request_id, hash, provider, model) do
    case Repo.get_by(Thread, account_id: account.id, owner_id: user.id, request_id: request_id) do
      %Thread{request_hash: ^hash} -> :ok
      %Thread{} -> {:error, :request_conflict}
      nil -> Provider.validate_model(user, provider, model)
    end
  end

  def message(user, account, id, attrs) do
    with {:ok, thread} <- get(user, account, id),
         {:ok, request_id} <- uuid(attrs["request_id"]),
         {:ok, body} <- content(attrs["content"]),
         {:ok, _opts} <- Provider.client_opts(user, thread) do
      fn ->
        thread = lock_thread(thread.id)
        require_access!(user, account, thread)

        case Repo.get_by(Message, thread_id: thread.id, request_id: request_id) do
          %Message{body: ^body} ->
            history(thread)

          %Message{} ->
            Repo.rollback(:request_conflict)

          nil ->
            require_idle!(thread)
            message = append!(thread, %{kind: "human", body: body, request_id: request_id, author_id: user.id})
            enqueue!(thread, message.id)
            history(Repo.reload!(thread))
        end
      end
      |> transact()
      |> wake()
    end
  end

  def archive(user, account, id, status) when status in ["active", "archived"] do
    with {:ok, thread} <- get(user, account, id) do
      result =
        transact(fn ->
          thread = lock_thread(thread.id)
          require_access!(user, account, thread)
          status = if status == "active", do: :active, else: :archived

          if status != thread.status do
            cancel_archived_runs!(thread, status)
            update_thread!(thread, %{status: status, agent_status: "idle"})
          end

          history(Repo.reload!(thread))
        end)

      release_abandoned(thread)
      result
    end
  end

  def archive(_, _, _, _), do: {:error, :invalid_arguments}

  defp cancel_archived_runs!(thread, :archived) do
    # Archiving cannot establish whether an in-flight publication landed.
    Repo.update_all(
      from(r in Run, where: r.thread_id == ^thread.id and r.status == "running" and r.kind == "ship"),
      set: [status: "outcome_unknown", checkpoint: nil, session_id: nil]
    )

    Repo.update_all(from(r in Run, where: r.thread_id == ^thread.id and r.status in ^@active),
      set: [status: "cancelled", checkpoint: nil, session_id: nil]
    )
  end

  defp cancel_archived_runs!(_thread, :active), do: :ok

  def snapshot(user, account, :inbox) do
    with :ok <- authorize(user, account) do
      revision =
        Repo.one(
          from i in "thread_inboxes", where: i.account_id == ^account.id and i.owner_id == ^user.id, select: i.revision
        ) || 0

      {:ok, %{revision: revision, agent_status: "idle"}}
    end
  end

  def snapshot(user, account, id) do
    with :ok <- authorize(user, account), {:ok, id} <- uuid(id) do
      case Repo.get_by(Thread, id: id, account_id: account.id, owner_id: user.id) do
        nil -> {:error, :not_found}
        thread -> {:ok, %{revision: thread.revision, agent_status: thread.agent_status}}
      end
    end
  end

  def ship_preview(user, account, id) do
    with {:ok, thread} <- get(user, account, id),
         {:ok, preview} <- Shipping.preview(user, thread) do
      transact(fn ->
        fresh = lock_thread(thread.id)
        require_access!(user, account, fresh)
        require_idle!(fresh)

        if fresh.base_sha != preview.base_sha or fresh.sandbox_id != preview.sandbox_id,
          do: Repo.rollback(:shipping_review_stale)

        Repo.insert!(struct(Approval, Map.delete(preview, :actor)), log: false)
        Map.update!(preview, :mode, &to_string/1)
      end)
    end
  end

  def ship(user, account, id, attrs) do
    with {:ok, thread} <- get(user, account, id), {:ok, request_id} <- uuid(attrs["request_id"]) do
      transact(fn ->
        thread = lock_thread(thread.id)
        require_access!(user, account, thread)

        approval =
          Repo.one(
            from a in Approval, where: a.thread_id == ^thread.id and a.request_id == ^request_id, lock: "FOR UPDATE"
          )

        if is_nil(approval) or approval.head_sha != attrs["head_sha"] or approval.base_sha != attrs["base_sha"] or
             approval.target_branch != attrs["target_branch"] or to_string(approval.mode) != attrs["mode"],
           do: Repo.rollback(:shipping_approval_invalid)

        if approval.status == :pending do
          require_idle!(thread)
          Repo.update!(Changeset.change(approval, status: :approved, approved_by_id: user.id, approved_at: now()))
          run = Repo.insert!(%Run{thread_id: thread.id, approval_id: approval.id, kind: "ship"})
          insert_job!(run)
          update_thread!(thread, %{agent_status: "shipping"})
        end

        history(Repo.reload!(thread))
      end)
    end
  end

  def reconcile_ship(user, account, id, attrs) do
    with {:ok, thread} <- get(user, account, id),
         {:ok, request_id} <- uuid(attrs["request_id"]),
         %Approval{} = approval <- Repo.get_by(Approval, thread_id: thread.id, request_id: request_id),
         {:ok, _} <- Shipping.reconcile(thread, approval) do
      transact(fn ->
        thread = lock_thread(thread.id)
        require_access!(user, account, thread)

        run =
          Repo.one(
            from r in Run,
              where: r.thread_id == ^thread.id and r.approval_id == ^approval.id and r.status == "outcome_unknown",
              lock: "FOR UPDATE"
          )

        if is_nil(run), do: Repo.rollback(:stale_run)
        Repo.update!(Changeset.change(run, status: "succeeded", checkpoint: nil, session_id: nil))
        Repo.update!(Changeset.change(approval, status: :succeeded))
        thread = update_thread!(thread, %{base_sha: approval.head_sha, agent_status: "idle"})

        append!(thread, %{
          kind: "notice",
          body: "GitHub confirms the exact reviewed changes were shipped. Publication was not repeated."
        })

        history(Repo.reload!(thread))
      end)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Claims a queued Ship run for its Oban job: a new attempt, fenced by the
  run's heartbeat.
  """
  def claim(id), do: claim(id, nil)

  @doc """
  Claims an inference run for the agents host holding the thread's session
  lease at `epoch` (`Tuist.Agents.Lease`): a queued run, or a running one an
  earlier host was interrupted in, which the new host resumes. The run's
  attempt becomes the epoch, so the lease fences its effects
  (`owns_run?/2`), and its Condukt session is the thread's own, by id.
  """
  def claim(id, epoch) do
    result =
      transact(fn ->
        run = Repo.get!(Run, id)
        thread = lock_thread(run.thread_id)
        run = Repo.one!(from r in Run, where: r.id == ^id, lock: "FOR UPDATE")
        if not claimable?(run, epoch) or not lease_held?(thread, epoch), do: Repo.rollback(:stale_run)
        claim_locked(thread, run, epoch)
      end)

    case result do
      {:ok, outcome} when outcome in [:forbidden, :expired] -> {:error, outcome}
      other -> other
    end
  end

  defp claim_locked(thread, run, epoch) do
    cond do
      # Commit the terminal state before acknowledging the forbidden job.
      # Rolling back here would leave it queued for every recovery sweep.
      thread.status != :active or not worker_access?(thread) ->
        interrupt!(thread, run)
        :forbidden

      # Each host gives a run a fresh budget, so a run handed on by every
      # deploy or outage would never end; its age, from the database's
      # clock, bounds them all.
      epoch && expired?(run) ->
        expire!(thread, run)
        :expired

      true ->
        claim!(thread, run, epoch)
    end
  end

  defp claim!(thread, run, epoch) do
    {attempt, session_id} =
      if is_nil(epoch), do: {run.attempt + 1, Ecto.UUID.generate()}, else: {epoch, thread.id}

    run =
      Repo.update!(
        Changeset.change(run,
          status: "running",
          attempt: attempt,
          session_id: session_id,
          heartbeat_at: now()
        )
      )

    if run.approval_id,
      do: Repo.update_all(from(a in Approval, where: a.id == ^run.approval_id), set: [status: :executing])

    thread = update_thread!(thread, %{agent_status: if(run.kind == "ship", do: "shipping", else: "running")})
    {run, thread}
  end

  # A host claims only while it holds the thread's lease at its epoch: one
  # whose lease lapsed, and that has not been drained yet, still receives the
  # thread's wakes, and must not start work the new host also starts.
  defp lease_held?(_thread, nil), do: true

  defp lease_held?(thread, epoch) do
    Repo.exists?(
      from s in "agent_sessions",
        where:
          s.id == ^to_string(thread.id) and s.epoch == ^epoch and
            s.lease_expires_at > fragment("CURRENT_TIMESTAMP")
    )
  end

  defp expired?(run) do
    Repo.exists?(
      from r in Run,
        where:
          r.id == ^run.id and r.inserted_at < fragment("CURRENT_TIMESTAMP - make_interval(hours => ?)", ^@run_max_hours)
    )
  end

  defp expire!(thread, run) do
    unknown = Repo.exists?(from c in ToolCall, where: c.run_id == ^run.id and c.status == "executing")
    status = if unknown, do: "outcome_unknown", else: "failed"

    Repo.update!(Changeset.change(run, status: status, session_id: nil))
    thread |> update_thread!(%{agent_status: status}) |> Push.notify_thread_finished(status)

    append!(Repo.reload!(thread), %{
      kind: "notice",
      body:
        "This run did not finish within #{@run_max_hours} hours, so it was stopped. Unknown tool effects are never automatically repeated. Send a new message to continue."
    })
  end

  defp claimable?(%Run{kind: "ship"} = run, nil), do: run.status == "queued"
  defp claimable?(%Run{kind: "ship"}, _epoch), do: false
  defp claimable?(_run, nil), do: false
  # A later epoch only: the host that took the lease over, never the same
  # host claiming twice nor an older one.
  defp claimable?(run, epoch), do: run.status in @active and epoch > run.attempt

  @doc """
  Whether attempt `attempt` still owns the run: a Ship attempt while its
  heartbeat is fresh, an inference attempt while its host holds the thread's
  session lease at that epoch.
  """
  def owns_run?(id, attempt) do
    Repo.exists?(
      from r in Run,
        join: t in Thread,
        on: t.id == r.thread_id,
        left_join: s in "agent_sessions",
        on: s.id == fragment("?::text", t.id) and s.epoch == r.attempt,
        where: r.id == ^id and r.attempt == ^attempt and r.status == "running" and t.status == :active,
        where: ^held()
    ) and
      worker_access?(Repo.get!(Thread, Repo.get!(Run, id).thread_id))
  end

  defp held do
    dynamic(
      [r, _t, s],
      (r.kind == "ship" and r.heartbeat_at > fragment("CURRENT_TIMESTAMP - interval '45 seconds'")) or
        (r.kind != "ship" and s.lease_expires_at > fragment("CURRENT_TIMESTAMP"))
    )
  end

  @doc "The thread's inference run its host should work on next, queued or interrupted."
  def next_run(thread_id) do
    Repo.one(
      from r in Run,
        where: r.thread_id == ^thread_id and r.kind != "ship" and r.status in ^@active,
        order_by: [asc: r.inserted_at, asc: r.id],
        select: r.id,
        limit: 1
    )
  end

  @doc """
  Refreshes an inference run's heartbeat while its host runs it. The lease,
  not the heartbeat, fences inference runs; the heartbeat only keeps the
  previous release's recovery sweep, which treats a run without a heartbeat
  in the last 60 seconds as abandoned, from interrupting it or giving it to
  an Oban job during a rolling deploy. It can go once no pod runs that
  release.
  """
  def keep_alive(run) do
    Repo.update_all(
      from(r in Run,
        where: r.id == ^run.id and r.attempt == ^run.attempt and r.status == "running" and r.kind != "ship"
      ),
      [set: [heartbeat_at: now()]],
      log: false
    )

    :ok
  end

  def heartbeat(run) do
    query =
      from r in Run,
        where:
          r.id == ^run.id and r.attempt == ^run.attempt and r.status == "running" and
            r.heartbeat_at > fragment("CURRENT_TIMESTAMP - interval '45 seconds'"),
        update: [set: [heartbeat_at: fragment("date_trunc('second', CURRENT_TIMESTAMP)")]]

    case Repo.update_all(query, [], timeout: 5_000) do
      {1, _} -> :ok
      _ -> {:error, :stale_run}
    end
  end

  def with_attempt(run, fun) do
    transact(fn ->
      thread = lock_thread(run.thread_id)
      fresh = Repo.one!(from r in Run, where: r.id == ^run.id, lock: "FOR UPDATE")

      if fresh.status != "running" or fresh.attempt != run.attempt or not owns_run?(run.id, run.attempt),
        do: Repo.rollback(:stale_run)

      require_worker_access!(thread)
      fun.(thread, fresh)
    end)
  end

  @doc """
  Records `thread`'s checkout as ready, with its repository, branches and
  base. A thread works on one repository: one bound meanwhile to another
  refuses the binding.
  """
  def bind_workspace(thread, run_id, attempt, sandbox_id, base_sha) do
    with_attempt(%{thread_id: thread.id, id: run_id, attempt: attempt}, fn fresh, _ ->
      if fresh.repository not in [nil, thread.repository], do: Repo.rollback(:repository_attached)

      update_thread!(fresh, %{
        repository: thread.repository,
        base_branch: thread.base_branch,
        branch: thread.branch,
        sandbox_id: sandbox_id,
        base_sha: base_sha,
        workspace_ready: true
      })
    end)
  end

  def bind_sandbox(thread_id, run_id, attempt, sandbox_id) do
    with_attempt(%{thread_id: thread_id, id: run_id, attempt: attempt}, fn thread, _ ->
      update_thread!(thread, %{sandbox_id: sandbox_id})
    end)
  end

  def rename(run, name) do
    if is_binary(name) and String.trim(name) != "" and String.length(name) <= 120 do
      with_attempt(run, fn thread, _ ->
        update_thread!(thread, %{title: String.trim(name)})
        "Thread renamed."
      end)
    else
      {:error, :invalid_arguments}
    end
  end

  @doc """
  Shows a card `Tuist.Threads.Cards` built as the run's next message: its
  NSH `source` at `size`, and `summary` as its text where it can't run. A
  resumed run showing the same card again finds it already shown.
  """
  def show_card(run, summary, size, source) do
    with_attempt(run, fn thread, _ ->
      %Message{position: since} = Repo.get!(Message, run.message_id)

      shown =
        from m in Message,
          where:
            m.thread_id == ^thread.id and m.kind == "card" and m.position > ^since and m.card_size == ^size and
              m.card_source == ^source

      if !Repo.exists?(shown),
        do: append!(thread, %{kind: "card", body: summary, card_size: size, card_source: source})

      "The card is shown in the conversation above your reply. Don't repeat what it shows."
    end)
  end

  def call_external_tool(run, invocation_id, name, args, dispatch) do
    # Condukt may admit a parallel batch. Contention must fail before reserving
    # an effect, not masquerade as an interrupted command that may have run.
    Workspace.exclusive(run.thread_id, fn ->
      key = fingerprint({invocation_id, name, args})

      reservation =
        with_attempt(run, fn thread, _ ->
          reserve_tool!(run, thread, key, name)
        end)

      case reservation do
        {:ok, {:replay, result}} ->
          {:ok, result}

        {:ok, {:dispatch, call}} ->
          execute_tool(run, call, dispatch)

        error ->
          error
      end
    end)
  end

  @doc """
  Records a call to a tool the person's app ran (`Tuist.Threads.Clients`)
  as a completed tool message, once the app answered. Unlike the other tools,
  no call is reserved before it runs: its effect stays on the device, so a
  call cut short leaves nothing that could block the thread.
  """
  def record_client_tool(run, name, result) do
    with_attempt(run, fn thread, _ ->
      append!(thread, %{
        kind: "tool",
        body: result |> tool_output() |> String.slice(0, 8000),
        tool_name: name,
        tool_state: "complete"
      })

      :ok
    end)
  end

  @doc """
  Reserves a built-in tool call of the run's Condukt session before it runs,
  as `Tuist.Threads.ToolLog` asks: records its intent and the thread's
  running tool message. Returns `:ok`, or `{:block, reason}` for a call that
  already ran or follows one whose outcome is unknown. Condukt orders the
  session's calls by their effects, so this run's calls to the built-in
  `tools` that are running or parked do not block it; any other open call
  does, such as an external tool call whose outcome is unknown.
  """
  def begin_tool_call(run, call_id, name, args, tools) do
    key = fingerprint({:session_call, call_id, name, args})

    case with_attempt(run, fn thread, _ -> reserve_tool!(run, thread, key, name, {:session, tools}) end) do
      {:ok, {:dispatch, _call}} ->
        :ok

      {:ok, {:replay, result}} ->
        {:block, "This tool call already ran. Its result was:\n\n" <> result}

      {:error, :tool_outcome_unknown} ->
        {:block, "An earlier tool call's outcome is unknown, so this call did not run."}

      {:error, :stale_run} ->
        {:block, "This run no longer owns the thread."}

      {:error, reason} ->
        {:block, "The tool call was refused: #{inspect(reason)}"}
    end
  end

  @doc """
  Records the result of a call `begin_tool_call/5` reserved, once it has its
  final result, after the last wake of a call that parked.
  """
  def complete_tool_call(run, call_id, name, args, result) do
    key = fingerprint({:session_call, call_id, name, args})

    case Repo.get_by(ToolCall, run_id: run.id, fingerprint: key, status: "executing") do
      nil -> :ok
      call -> with {:ok, _output} <- complete_tool!(run, call, tool_output(result)), do: :ok
    end
  end

  @doc """
  Records the run's calls to the built-in tools `names` that are still
  executing as cancelled. Call it once the run's session has stopped:
  stopping it killed those calls and the commands they started, so no result
  follows, and an open call would otherwise leave the thread's outcome
  unknown. Calls to other tools, which record themselves, keep theirs.
  """
  def cancel_tool_calls(run, names) do
    with_attempt(run, fn _thread, _ ->
      from(c in ToolCall, where: c.run_id == ^run.id and c.status == "executing" and c.name in ^names)
      |> Repo.all()
      |> Enum.each(
        &complete_tool!(run, &1, "Cancelled: the run ended before this call finished, so it may have partly run.")
      )
    end)
  end

  defp tool_output({:ok, text}) when is_binary(text), do: text
  defp tool_output({:ok, value}), do: inspect(value)
  defp tool_output({:error, reason}) when is_binary(reason), do: "Tool failed: " <> reason
  defp tool_output({:error, reason}), do: "Tool failed: " <> inspect(reason)

  defp reserve_tool!(run, thread, key, name, scope \\ :thread) do
    case Repo.get_by(ToolCall, run_id: run.id, fingerprint: key) do
      %ToolCall{status: "completed", result: result} ->
        {:replay, result}

      # The same call of the same run, which a resumed session reruns because
      # its tool is replay-safe: it follows what the interrupted call started.
      %ToolCall{} = call when is_tuple(scope) ->
        {:dispatch, call}

      %ToolCall{} ->
        Repo.rollback(:tool_outcome_unknown)

      nil ->
        reserve_new_tool!(run, thread, key, name, scope)
    end
  end

  defp reserve_new_tool!(run, thread, key, name, scope) do
    executing =
      from c in ToolCall,
        join: r in Run,
        on: r.id == c.run_id,
        where: r.thread_id == ^thread.id and c.status == "executing"

    executing =
      case scope do
        :thread -> executing
        {:session, tools} -> where(executing, [c], c.run_id != ^run.id or c.name not in ^tools)
      end

    if Repo.exists?(executing), do: Repo.rollback(:tool_outcome_unknown)

    message = append!(thread, %{kind: "tool", body: "Working…", tool_name: name, tool_state: "running"})
    call = Repo.insert!(%ToolCall{run_id: run.id, message_id: message.id, fingerprint: key, name: name})
    {:dispatch, call}
  end

  defp execute_tool(run, call, dispatch) do
    # Intent commits before execution. A crash here is uncertain, not a retry.
    result = dispatch.()

    output =
      case result do
        {:ok, output} -> output
        {:error, reason} -> "Tool failed: #{reason}"
      end

    # Transport errors may follow a completed shell side effect. Keep the
    # reservation unresolved and block later tools instead of guessing.
    if match?({:ok, _}, result) or result == {:error, :invalid_arguments} do
      complete_tool!(run, call, output)
    else
      {:error, :tool_outcome_unknown}
    end
  end

  defp complete_tool!(run, call, output) do
    with_attempt(run, fn thread, _ ->
      Repo.update!(Changeset.change(call, status: "completed", result: output), log: false)
      message = Repo.get!(Message, call.message_id)

      Repo.update!(Changeset.change(message, body: String.slice(output, 0, 8000), tool_state: "complete"),
        log: false
      )

      update_thread!(thread, %{})
      output
    end)
  end

  @doc """
  Ends a run its host could not continue, such as one whose process crashed,
  as interrupted, or as `outcome_unknown` while a tool call's effect is
  unknown. Fenced like `finish/2`: only the attempt that owns the run may.
  """
  def abandon(run) do
    with_attempt(run, fn thread, fresh -> interrupt!(thread, fresh) end)
  end

  def finish(run, result) do
    with_attempt(run, fn thread, fresh ->
      unknown = Repo.exists?(from c in ToolCall, where: c.run_id == ^run.id and c.status == "executing")
      {status, body, suggestions} = run_outcome(thread, fresh, {unknown, result})

      if fresh.approval_id && status == "failed",
        do: Repo.update_all(from(a in Approval, where: a.id == ^fresh.approval_id), set: [status: :failed])

      Repo.update!(
        Changeset.change(fresh,
          status: if(status == "idle", do: "succeeded", else: status),
          checkpoint: nil,
          session_id: nil
        )
      )

      thread = Repo.reload!(thread)
      append!(thread, %{kind: if(status == "idle", do: "agent", else: "notice"), body: body, suggestions: suggestions})
      thread = update_thread!(Repo.reload!(thread), %{agent_status: status})
      Push.notify_thread_finished(thread, status)
      thread
    end)
  end

  defp run_outcome(_thread, _run, {true, _}) do
    {"outcome_unknown",
     "A tool was interrupted. Its effects are unknown; further workspace changes are blocked. Inspect the workspace before continuing.",
     []}
  end

  defp run_outcome(_thread, _run, {false, {:ok, text}}) when is_binary(text) do
    {reply, suggestions} = Agent.decode_reply(text)
    {"idle", reply, suggestions}
  end

  defp run_outcome(thread, run, {false, {:ok, %{head_sha: sha}}}) do
    Repo.update!(Changeset.change(thread, base_sha: sha))
    Repo.update_all(from(a in Approval, where: a.id == ^run.approval_id), set: [status: :succeeded])

    {"idle", "Shipped the reviewed changes using the GitHub App. No deployment was triggered by Tuist Threads.", []}
  end

  defp run_outcome(_thread, _run, {false, {:error, :shipping_uncertain}}) do
    {"outcome_unknown",
     "The connection ended before Ship could confirm its result. Further changes are blocked until the reviewed destination is reconciled; the push is not automatically repeated.",
     []}
  end

  defp run_outcome(_thread, _run, {false, {:error, reason}}) when reason in [:pull_request_required, :protected_branch] do
    {"failed",
     "Repository protection prevents this Ship. Follow the repository's required review and checks; Threads will not bypass them.",
     []}
  end

  defp run_outcome(_thread, _run, {false, {:error, reason}})
       when reason in [:shipping_base_changed, :shipping_review_stale] do
    {"failed",
     "The repository or workspace changed since review. Review the current changes again before approving Ship.", []}
  end

  defp run_outcome(_thread, _run, {false, {:error, {failure, _reason}}})
       when failure in [:snapshot_load_failed, :journal_load_failed] do
    {"failed",
     "This thread's saved conversation could not be read, so it cannot continue. Start a new thread to keep working.", []}
  end

  defp run_outcome(_thread, _run, {false, _}) do
    {"failed",
     "The run could not complete. Check the connected AI account and workspace, then send a new message to retry.", []}
  end

  def recover do
    want_orphaned_sessions()

    candidates =
      Repo.all(
        from r in Run,
          # Inference runs are hosted under session leases (`Tuist.Agents`),
          # which a lapsed host hands on by itself; only Ship runs are jobs.
          where:
            r.kind == "ship" and r.status in ^@active and
              (is_nil(r.heartbeat_at) or r.heartbeat_at < fragment("CURRENT_TIMESTAMP - interval '60 seconds'")),
          order_by: [asc_nulls_last: r.heartbeat_at, asc: r.id],
          limit: 100
      )

    Enum.each(candidates, &recover_run/1)
    :ok
  end

  # Inference runs an earlier release left running, as when its Oban job
  # ended without finishing the run: no host keeps their heartbeat fresh, no
  # host holds or wants their session, and nothing else would pick them up.
  # Their sessions want a host, which resumes or ends them at a later epoch.
  defp want_orphaned_sessions do
    from(r in Run,
      left_join: s in "agent_sessions",
      on: s.id == fragment("?::text", r.thread_id),
      where:
        r.kind != "ship" and r.status == "running" and
          (is_nil(r.heartbeat_at) or r.heartbeat_at < fragment("CURRENT_TIMESTAMP - interval '60 seconds'")),
      where:
        is_nil(s.id) or
          (s.wanted == false and is_nil(s.deleted_at) and
             (is_nil(s.lease_expires_at) or s.lease_expires_at < fragment("CURRENT_TIMESTAMP"))),
      select: {r.thread_id, r.attempt},
      limit: 100
    )
    |> Repo.all()
    |> Enum.each(fn {thread_id, attempt} ->
      Lease.want(to_string(thread_id), "thread", min_epoch: attempt)
      Lease.wake(to_string(thread_id))
    end)
  end

  defp recover_run(candidate) do
    result =
      transact(fn ->
        thread = lock_thread(candidate.thread_id)
        run = Repo.one!(from r in Run, where: r.id == ^candidate.id, lock: "FOR UPDATE")
        recover_locked(thread, run)
        thread
      end)

    case result do
      {:ok, thread} -> release_abandoned(thread)
      _ -> :ok
    end
  end

  defp recover_locked(thread, run) do
    cond do
      run.status == "queued" and (thread.status != :active or not worker_access?(thread)) ->
        interrupt!(thread, run)

      run.status == "queued" ->
        insert_job!(run)

      run.status != "running" ->
        :ok

      not is_nil(run.heartbeat_at) and DateTime.diff(now(), run.heartbeat_at) < 60 ->
        :ok

      true ->
        interrupt!(thread, run)
    end
  end

  # Ends a run no attempt may continue: a Ship whose attempt lapsed, or a run
  # whose owner lost access. An interrupted inference run its host can still
  # continue is resumed from its session's journal instead.
  defp interrupt!(thread, run) do
    unknown = Repo.exists?(from c in ToolCall, where: c.run_id == ^run.id and c.status == "executing")
    status = if run.kind == "ship" or unknown, do: "outcome_unknown", else: "interrupted"

    Repo.update!(Changeset.change(run, status: status, session_id: nil))
    thread = update_thread!(thread, %{agent_status: status})
    # An archived thread, or one in an account its owner left, isn't worth a notification they can't act on.
    if thread.status == :active and worker_access?(thread), do: Push.notify_thread_finished(thread, status)

    append!(Repo.reload!(thread), %{
      kind: "notice",
      body: "Execution was interrupted. Unknown tool effects are never automatically repeated."
    })
  end

  def serialize(thread) do
    %{
      id: thread.id,
      title: thread.title,
      goal: thread.goal,
      provider: thread.provider,
      model: thread.model,
      repository: thread.repository || "",
      branch: thread.branch || "",
      profile: "linux",
      status: thread.agent_status,
      visibility: "private",
      archive_status: to_string(thread.status),
      revision: thread.revision,
      has_more: thread.has_more,
      next_before: thread.next_before,
      diff: "",
      messages: Enum.map(thread.messages, &serialize_message/1)
    }
  end

  def history(thread, before \\ nil) do
    query = from m in Message, where: m.thread_id == ^thread.id
    query = if before, do: from(m in query, where: m.position < ^before), else: query
    rows = Repo.all(from m in query, order_by: [desc: m.position], limit: 51)
    messages = rows |> Enum.take(50) |> Enum.reverse()

    %{
      thread
      | messages: messages,
        has_more: length(rows) > 50,
        next_before: if(length(rows) > 50, do: hd(messages).position)
    }
  end

  defp serialize_message(%Message{kind: "card"} = message) do
    message
    |> Map.put(:kind, "agent")
    |> serialize_message()
    |> Map.put(:ui, %{size: message.card_size, source: message.card_source})
  end

  defp serialize_message(message) do
    %{
      id: message.id,
      role:
        case message.kind do
          "human" -> "user"
          "agent" -> "assistant"
          "tool" -> "tool"
          _ -> "system"
        end,
      content: message.body || "",
      position: message.position,
      toolName: message.tool_name,
      toolStatus: message.tool_state,
      suggestions: message.suggestions,
      createdAt: DateTime.to_iso8601(message.inserted_at)
    }
  end

  @doc """
  Clears the repository of a thread whose checkout can never succeed, such
  as one too large to check out, while nothing is checked out. Fenced to the
  run's attempt like `bind_workspace/5`.
  """
  def unbind_repository(thread, run_id, attempt) do
    with_attempt(%{thread_id: thread.id, id: run_id, attempt: attempt}, fn fresh, _ ->
      if fresh.workspace_ready, do: Repo.rollback(:workspace_ready)
      update_thread!(fresh, %{repository: nil, base_branch: nil, branch: nil})
    end)
  end

  @doc """
  Makes the repository `attrs` names (`repository/3`) the thread's one
  repository, on the agent's request during `run`, when the thread's owner
  can read it on GitHub and its base branch exists. The caller checks it
  out (`Workspace.attach/1`), or the next run's `Workspace.prepare/2` does.
  """
  def request_repository(run, attrs) do
    thread = Repo.get!(Thread, run.thread_id)

    with {:ok, account} <- Accounts.get_account_by_id(thread.account_id),
         owner when not is_nil(owner) <- Accounts.get_user_by_id(thread.owner_id),
         {:ok, name, base_branch} when is_binary(name) <- repository(account, owner, attrs),
         {:ok, _sha} <- Repository.branch_head(account, name, base_branch) do
      with_attempt(run, fn thread, _ ->
        cond do
          thread.repository == name ->
            {:attached, name, thread.base_branch}

          not is_nil(thread.repository) ->
            Repo.rollback(:repository_attached)

          true ->
            update_thread!(thread, %{repository: name, base_branch: base_branch, branch: "threads/#{thread.id}"})
            {:attached, name, base_branch}
        end
      end)
    else
      {:ok, nil, nil} -> {:error, :invalid_arguments}
      nil -> {:error, :forbidden}
      {:error, _} = error -> error
    end
  end

  @doc """
  The account's repository `attrs["repository"]` names, canonicalized, if
  `owner` can read it on GitHub (`Repository.authorize/4`), and
  its base branch (`attrs["base_branch"]`, else the default branch), or nil
  for none.
  """
  def repository(_account, _owner, %{"repository" => value}) when value in [nil, ""], do: {:ok, nil, nil}

  def repository(account, owner, %{"repository" => name} = attrs) do
    with {:ok, repository} <- Repository.authorize(account, owner, name),
         :ok <- Checkout.fits(repository) do
      branch = attrs["base_branch"] || repository.default_branch

      if is_binary(branch) and byte_size(branch) <= 255 and Regex.match?(~r/\A[\w][\w.\/-]*\z/u, branch) and
           not String.contains?(branch, ["..", "//", "@{"]),
         do: {:ok, repository.name, branch},
         else: {:error, :invalid_arguments}
    end
  end

  def repository(_, _, _), do: {:ok, nil, nil}

  defp require_access!(user, account, thread) do
    if thread.owner_id != user.id or authorize(user, account) != :ok, do: Repo.rollback(:forbidden)
  end

  defp require_idle!(thread) do
    if thread.status != :active, do: Repo.rollback(:archived)

    if thread.agent_status == "outcome_unknown" or
         Repo.exists?(from r in Run, where: r.thread_id == ^thread.id and r.status == "outcome_unknown") or
         Repo.exists?(
           from c in ToolCall,
             join: r in Run,
             on: r.id == c.run_id,
             where: r.thread_id == ^thread.id and c.status == "executing"
         ),
       do: Repo.rollback(:tool_outcome_unknown)

    if Repo.exists?(from r in Run, where: r.thread_id == ^thread.id and r.status in ^@active), do: Repo.rollback(:busy)
  end

  defp require_worker_access!(thread) do
    if not worker_access?(thread) or thread.status != :active, do: Repo.rollback(:forbidden)
  end

  defp worker_access?(thread) do
    with %User{} = user <- Accounts.get_user_by_id(thread.owner_id),
         {:ok, account} <- Accounts.get_account_by_id(thread.account_id) do
      authorize(user, account) == :ok
    else
      _ -> false
    end
  end

  defp lock_thread(id), do: Repo.one!(from t in Thread, where: t.id == ^id, lock: "FOR UPDATE")

  defp append!(thread, attrs) do
    # Caller holds the thread lock. Sequence is stable even if a tool card updates.
    thread = Repo.reload!(thread)
    thread = update_thread!(thread, %{})
    Repo.insert!(struct(Message, Map.merge(attrs, %{thread_id: thread.id, position: thread.revision})), log: false)
  end

  defp update_thread!(thread, attrs) do
    thread =
      Repo.update!(Changeset.change(thread, Map.merge(attrs, %{revision: thread.revision + 1, updated_at: now()})),
        log: false
      )

    Repo.insert_all("thread_inboxes", [%{owner_id: thread.owner_id, account_id: thread.account_id, revision: 1}],
      conflict_target: [:owner_id, :account_id],
      on_conflict: from(i in "thread_inboxes", update: [inc: [revision: 1]])
    )

    Phoenix.PubSub.broadcast(Tuist.PubSub, topic(thread.owner_id, thread.account_id), :threads_changed)
    thread
  end

  # The run and the session's want commit together; the host is told on
  # commit, and once more by `wake/1` after it.
  defp enqueue!(thread, message_id) do
    # Fresh, so the previous release's recovery sweep, which still runs on its
    # pods during a rolling deploy, does not give the run to an Oban job
    # before a host claims it (`keep_alive/1`).
    Repo.insert!(%Run{thread_id: thread.id, message_id: message_id, heartbeat_at: now()})
    Lease.want(thread.id, "thread")
    update_thread!(Repo.reload!(thread), %{agent_status: "queued"})
  end

  defp wake({:ok, %Thread{id: id}} = result) do
    Lease.wake(id)
    result
  end

  defp wake(result), do: result

  defp insert_job!(run) do
    %{run_id: run.id, attempt: run.attempt} |> Worker.new() |> Oban.insert!()
  end

  defp release_abandoned(%{sandbox_id: nil}), do: :ok

  defp release_abandoned(thread) do
    case Sandboxes.get_sandbox_by_id(thread.sandbox_id) do
      %{residency_work_id: work_id} = sandbox when is_binary(work_id) ->
        if String.starts_with?(work_id, ["threads:", "threads-ship:"]) and
             not Repo.exists?(from r in Run, where: r.thread_id == ^thread.id and r.status == "running"),
           do: Workspace.release(%{sandbox: sandbox, residency: work_id})

      _ ->
        :ok
    end
  end

  defp transact(fun), do: Repo.transaction(fun, log: false)

  defp now do
    %{rows: [[timestamp]]} = Repo.query!("SELECT date_trunc('second', CURRENT_TIMESTAMP)", [], log: false)
    DateTime.truncate(timestamp, :second)
  end

  defp fingerprint(value), do: :crypto.hash(:sha256, :erlang.term_to_binary(value, [:deterministic]))

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :invalid_arguments}
    end
  end

  defp content(value) when is_binary(value) do
    if String.valid?(value) and String.trim(value) != "" and byte_size(value) <= 16_000,
      do: {:ok, value},
      else: {:error, :invalid_arguments}
  end

  defp content(_), do: {:error, :invalid_arguments}
  defp before_position(nil), do: {:ok, nil}
  defp before_position(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp before_position(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> {:ok, number}
      _ -> {:error, :invalid_arguments}
    end
  end

  defp before_position(_), do: {:error, :invalid_arguments}
  defp decode_cursor(nil), do: {:ok, nil}

  defp decode_cursor(cursor) when is_binary(cursor) and byte_size(cursor) <= 256 do
    with {:ok, data} <- Base.url_decode64(cursor, padding: false),
         {:ok, [timestamp, id]} <- JSON.decode(data),
         {:ok, timestamp, _} <- DateTime.from_iso8601(timestamp),
         {:ok, id} <- uuid(id) do
      {:ok, {timestamp, id}}
    else
      _ -> {:error, :invalid_arguments}
    end
  end

  defp decode_cursor(_), do: {:error, :invalid_arguments}
end
