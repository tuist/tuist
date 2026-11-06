defmodule Tuist.Threads do
  @moduledoc """
  Private, durable conversations. PostgreSQL owns history, execution leases,
  tool reservations and Ship approvals; processes and sockets are disposable.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Threads.Agent
  alias Tuist.Threads.Approval
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

  def authorize(%User{active: true, disabled_at: nil} = user, account) when not is_nil(account) do
    if FeatureFlags.ai_enabled?(user) and Authorization.authorize(:account_update, user, account) == :ok,
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
         {:ok, repository, branch} <- repository(account, attrs),
         hash = fingerprint({body, repository, branch, provider, model}),
         :ok <- creation_model(user, account, request_id, hash, provider, model) do
      transact(fn ->
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

            message = append!(thread, %{kind: "human", body: body, request_id: request_id})
            enqueue!(thread, message.id)
            history(Repo.reload!(thread))

          %Thread{request_hash: ^hash} = thread ->
            history(thread)

          _ ->
            Repo.rollback(:request_conflict)
        end
      end)
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
      transact(fn ->
        thread = lock_thread(thread.id)
        require_access!(user, account, thread)

        case Repo.get_by(Message, thread_id: thread.id, request_id: request_id) do
          %Message{body: ^body} ->
            history(thread)

          %Message{} ->
            Repo.rollback(:request_conflict)

          nil ->
            require_idle!(thread)
            message = append!(thread, %{kind: "human", body: body, request_id: request_id})
            enqueue!(thread, message.id)
            history(Repo.reload!(thread))
        end
      end)
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

  def claim(id) do
    result =
      transact(fn ->
        run = Repo.get!(Run, id)
        thread = lock_thread(run.thread_id)
        run = Repo.one!(from r in Run, where: r.id == ^id, lock: "FOR UPDATE")
        if run.status != "queued", do: Repo.rollback(:stale_run)

        if thread.status != :active or not worker_access?(thread) do
          # Commit the terminal state before acknowledging the forbidden job.
          # Rolling back here would leave it queued for every recovery sweep.
          resume_or_interrupt!(thread, run, true)
          :forbidden
        else
          run =
            Repo.update!(
              Changeset.change(run,
                status: "running",
                attempt: run.attempt + 1,
                session_id: Ecto.UUID.generate(),
                heartbeat_at: now()
              )
            )

          if run.approval_id,
            do: Repo.update_all(from(a in Approval, where: a.id == ^run.approval_id), set: [status: :executing])

          thread = update_thread!(thread, %{agent_status: if(run.kind == "ship", do: "shipping", else: "running")})
          {run, thread}
        end
      end)

    case result do
      {:ok, :forbidden} -> {:error, :forbidden}
      other -> other
    end
  end

  def owns_run?(id, attempt) do
    Repo.exists?(
      from r in Run,
        join: t in Thread,
        on: t.id == r.thread_id,
        where:
          r.id == ^id and r.attempt == ^attempt and r.status == "running" and t.status == :active and
            r.heartbeat_at > fragment("CURRENT_TIMESTAMP - interval '45 seconds'")
    ) and
      worker_access?(Repo.get!(Thread, Repo.get!(Run, id).thread_id))
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

  def bind_workspace(thread_id, run_id, attempt, sandbox_id, base_sha) do
    with_attempt(%{thread_id: thread_id, id: run_id, attempt: attempt}, fn thread, _ ->
      update_thread!(thread, %{sandbox_id: sandbox_id, base_sha: base_sha, workspace_ready: true})
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
        "Session renamed."
      end)
    else
      {:error, :invalid_arguments}
    end
  end

  def call_tool(run, context, name, args) do
    call_external_tool(run, context.invocation_id, name, args, fn -> Workspace.call(context, name, args) end)
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

  defp reserve_tool!(run, thread, key, name) do
    case Repo.get_by(ToolCall, run_id: run.id, fingerprint: key) do
      %ToolCall{status: "completed", result: result} ->
        {:replay, result}

      %ToolCall{} ->
        Repo.rollback(:tool_outcome_unknown)

      nil ->
        if Repo.exists?(
             from c in ToolCall,
               join: r in Run,
               on: r.id == c.run_id,
               where: r.thread_id == ^thread.id and c.status == "executing"
           ),
           do: Repo.rollback(:tool_outcome_unknown)

        message = append!(thread, %{kind: "tool", body: "Working…", tool_name: name, tool_state: "running"})
        call = Repo.insert!(%ToolCall{run_id: run.id, message_id: message.id, fingerprint: key, name: name})
        {:dispatch, call}
    end
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
      with_attempt(run, fn thread, _ ->
        Repo.update!(Changeset.change(call, status: "completed", result: output), log: false)
        message = Repo.get!(Message, call.message_id)

        Repo.update!(Changeset.change(message, body: String.slice(output, 0, 8000), tool_state: "complete"),
          log: false
        )

        update_thread!(thread, %{})
        output
      end)
    else
      {:error, :tool_outcome_unknown}
    end
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
      update_thread!(Repo.reload!(thread), %{agent_status: status})
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

  defp run_outcome(_thread, _run, {false, _}) do
    {"failed",
     "The run could not complete. Check the connected AI account and workspace, then send a new message to retry.", []}
  end

  def recover do
    candidates =
      Repo.all(
        from r in Run,
          where:
            r.status in ^@active and
              (is_nil(r.heartbeat_at) or r.heartbeat_at < fragment("CURRENT_TIMESTAMP - interval '60 seconds'")),
          order_by: [asc_nulls_last: r.heartbeat_at, asc: r.id],
          limit: 100
      )

    Enum.each(candidates, &recover_run/1)
    :ok
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
        resume_or_interrupt!(thread, run, true)

      run.status == "queued" ->
        insert_job!(run)

      run.status != "running" ->
        :ok

      not is_nil(run.heartbeat_at) and DateTime.diff(now(), run.heartbeat_at) < 60 ->
        :ok

      true ->
        resume_or_interrupt!(thread, run)
    end
  end

  defp resume_or_interrupt!(thread, run, access_revoked \\ false) do
    unknown = Repo.exists?(from c in ToolCall, where: c.run_id == ^run.id and c.status == "executing")
    uncheckpointed = Repo.exists?(from c in ToolCall, where: c.run_id == ^run.id and not c.checkpointed)

    terminal =
      access_revoked or unknown or uncheckpointed or run.kind == "ship" or run.attempt >= 3 or thread.status != :active or
        not worker_access?(thread)

    status = recovery_status(run, unknown, terminal)

    run = Repo.update!(Changeset.change(run, status: status, session_id: nil))
    update_thread!(thread, %{agent_status: status})

    if terminal do
      append!(Repo.reload!(thread), %{
        kind: "notice",
        body: "Execution was interrupted. Unknown tool effects are never automatically repeated."
      })
    else
      insert_job!(run)
    end
  end

  defp recovery_status(%{kind: "ship"}, _unknown, _terminal), do: "outcome_unknown"
  defp recovery_status(_run, true, _terminal), do: "outcome_unknown"
  defp recovery_status(_run, false, true), do: "interrupted"
  defp recovery_status(_run, false, false), do: "queued"

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

  defp repository(_account, %{"repository" => value}) when value in [nil, ""], do: {:ok, nil, nil}

  defp repository(account, %{"repository" => name} = attrs) do
    with {:ok, repository} <- Repository.authorize(account, name) do
      branch = attrs["base_branch"] || repository.default_branch

      if is_binary(branch) and byte_size(branch) <= 255 and Regex.match?(~r/\A[\w][\w.\/-]*\z/u, branch) and
           not String.contains?(branch, ["..", "//", "@{"]),
         do: {:ok, repository.name, branch},
         else: {:error, :invalid_arguments}
    end
  end

  defp repository(_, _), do: {:ok, nil, nil}

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

  defp enqueue!(thread, message_id) do
    run = Repo.insert!(%Run{thread_id: thread.id, message_id: message_id})
    insert_job!(run)
    update_thread!(Repo.reload!(thread), %{agent_status: "queued"})
  end

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
