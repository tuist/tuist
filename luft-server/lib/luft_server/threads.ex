defmodule LuftServer.Threads do
  @moduledoc """
  Local conversation storage authorized by a fresh Tuist scope.

  New inference work requires an explicit `:execution` adapter implementing
  `admit(scope, owner_session, author_session, selection)`. It must validate
  current owner entitlement, provider/model, repository and runner selection,
  and return `{:ok, normalized_selection}` only when execution is supported
  (`:ok` also accepts the requested selection). There is no fallback to
  Tuist threads. The default rejects new work with `:execution_unavailable`.
  Admission must not dispatch effects: work and its lease want commit here.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias LuftServer.Agents.Lease
  alias LuftServer.Notifications
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Sessions.Session
  alias LuftServer.Threads.Agent
  alias LuftServer.Threads.Approval
  alias LuftServer.Threads.BuildProgress
  alias LuftServer.Threads.Capabilities
  alias LuftServer.Threads.Checkout
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.Participant
  alias LuftServer.Threads.Provider
  alias LuftServer.Threads.Repository
  alias LuftServer.Threads.Run
  alias LuftServer.Threads.Shipping
  alias LuftServer.Threads.ShipWorker
  alias LuftServer.Threads.SnoozeWorker
  alias LuftServer.Threads.Thread
  alias LuftServer.Threads.ToolCall
  alias LuftServer.Tuist.Scope
  alias LuftServer.Workspaces.Records

  @working ~w(queued running compacting shipping)
  @unfinished ~w(queued running waiting)
  @mention ~r/(?<![A-Za-z0-9_.@-])@([A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)/

  def authorize(%Scope{can_create_threads: true}), do: :ok
  def authorize(_), do: {:error, :forbidden}

  def authorize_reader(%Scope{can_create_threads: true}), do: :ok
  def authorize_reader(%Scope{organization_id: id}) when is_integer(id), do: :ok
  def authorize_reader(_), do: {:error, :forbidden}

  def topic(user_id, account_id), do: "threads:#{account_id}:#{user_id}"

  def mentions(text) when is_binary(text) do
    @mention
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end

  def list(%Scope{} = scope, cursor \\ nil) do
    with :ok <- authorize_reader(scope), {:ok, boundary} <- decode_cursor(cursor) do
      shared = from p in Participant, where: p.user_id == ^scope.user_id, select: p.thread_id
      owned = scope.can_create_threads

      query =
        from t in Thread,
          where: t.account_id == ^scope.account_id,
          where: (^owned and t.owner_id == ^scope.user_id) or t.id in subquery(shared)

      query =
        if boundary do
          {timestamp, id} = boundary

          from t in query,
            where: t.updated_at < ^timestamp or (t.updated_at == ^timestamp and t.id < ^id)
        else
          query
        end

      rows = Repo.all(from t in query, order_by: [desc: t.updated_at, desc: t.id], limit: 26)
      page = Enum.take(rows, 25)
      last = List.last(page)

      next =
        if length(rows) > 25,
          do:
            Base.url_encode64(JSON.encode!([DateTime.to_iso8601(last.updated_at), last.id]),
              padding: false
            )

      {:ok, %{threads: Enum.map(page, &people(&1, scope)), next_cursor: next}}
    end
  end

  def get(%Scope{} = scope, id, opts \\ []) do
    with {:ok, id} <- uuid(id),
         %Thread{} = thread <- Repo.get_by(Thread, id: id, account_id: scope.account_id),
         :ok <- access(scope, thread),
         {:ok, before} <- before_position(Keyword.get(opts, :before)) do
      {:ok, history(thread, scope, before)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def create(scope, session, handle, attrs, opts \\ []) do
    with :ok <- authorize(scope),
         :ok <- delegation(session, scope.user_id),
         true <- is_binary(handle) and String.trim(handle) != "",
         {:ok, request_id} <- uuid(attrs["request_id"]),
         {:ok, files} <- attachments(attrs["attachments"]),
         {:ok, body} <- content(attrs["content"], files),
         {:ok, requested} <- selection(attrs) do
      selection = Map.put(requested, :account_handle, handle)

      value =
        {body, selection.repository, selection.base_branch, selection.provider, selection.model}

      value =
        if selection.runner_id,
          do: Tuple.insert_at(value, tuple_size(value), selection.runner_id),
          else: value

      hash = fingerprint(if files == [], do: value, else: {value, files})

      fn ->
        # There is no local account row: serialize first-use keys in PostgreSQL.
        key = "thread-create:#{scope.account_id}:#{scope.user_id}:#{request_id}"
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key], log: false)

        case Repo.get_by(Thread,
               account_id: scope.account_id,
               owner_id: scope.user_id,
               request_id: request_id
             ) do
          %Thread{request_hash: ^hash} = thread ->
            history(thread, scope)

          %Thread{} ->
            Repo.rollback(:request_conflict)

          nil ->
            selection = admit!(opts, scope, session, session, selection)
            id = Ecto.UUID.generate()

            thread =
              Repo.insert!(
                struct!(
                  Thread,
                  Map.merge(selection, %{
                    id: id,
                    account_id: scope.account_id,
                    account_handle: handle,
                    owner_id: scope.user_id,
                    owner_session_id: session.id,
                    request_id: request_id,
                    request_hash: hash,
                    title:
                      String.slice(
                        if(String.trim(body) == "", do: hd(files)["name"], else: body),
                        0,
                        80
                      ),
                    goal: body,
                    branch: if(selection.repository, do: "threads/#{id}")
                  })
                ),
                log: false
              )

            message = append!(thread, human(scope, session, body, files, request_id))
            loop_in!(thread, scope, body)
            enqueue!(thread, message.id)
            history(Repo.reload!(thread), scope)
        end
      end
      |> transact()
      |> wake()
    else
      false -> {:error, :invalid_arguments}
      error -> error
    end
  end

  def message(scope, session, id, attrs, opts \\ []) do
    with {:ok, thread} <- get(scope, id),
         :ok <- delegation(session, scope.user_id),
         {:ok, request_id} <- uuid(attrs["request_id"]),
         {:ok, files} <- attachments(attrs["attachments"]),
         {:ok, body} <- content(attrs["content"], files) do
      fn ->
        thread = lock(thread.id)
        require_access!(scope, thread)

        case Repo.get_by(Message, thread_id: thread.id, request_id: request_id) do
          %Message{kind: "human", author_id: author, body: ^body, attachments: ^files} = sent
          when author == scope.user_id ->
            Map.take(sent.decision || %{}, ~w(question_id option_id cancel)) ==
              Map.take(attrs, ~w(question_id option_id cancel)) or
              Repo.rollback(:request_conflict)

          %Message{} ->
            Repo.rollback(:request_conflict)

          nil ->
            prompt!(thread, scope, session, body, files, request_id, attrs, opts)
        end

        history(Repo.reload!(thread), scope)
      end
      |> transact()
      |> wake()
    end
  end

  def archive(scope, id, status) when status in ["active", "archived"] do
    with {:ok, thread} <- owned(scope, id) do
      transact(fn ->
        thread = lock(thread.id)
        require_access!(scope, thread)
        target = if status == "active", do: :active, else: :archived

        if target != thread.status and target == :archived, do: cancel_work!(thread)

        if target != thread.status do
          update!(thread, %{status: target, agent_status: "idle", snoozed_until_needed: false})
        end

        history(Repo.reload!(thread), scope)
      end)
    end
  end

  def archive(_, _, _), do: {:error, :invalid_arguments}

  defp cancel_work!(thread) do
    Repo.update_all(
      from(r in Run,
        where: r.thread_id == ^thread.id and r.status == "running" and r.kind == "ship"
      ),
      set: [status: "outcome_unknown", checkpoint: nil, session_id: nil]
    )

    Repo.update_all(
      from(r in Run, where: r.thread_id == ^thread.id and r.status in @unfinished),
      set: [status: "cancelled", checkpoint: nil, session_id: nil]
    )

    for question <-
          Repo.all(from m in Message, where: m.thread_id == ^thread.id and m.kind == "decision") do
      if question.decision && question.decision["status"] == "pending",
        do:
          Repo.update!(
            Changeset.change(question,
              decision: Map.put(question.decision, "status", "cancelled")
            ),
            log: false
          )
    end
  end

  @doc "Explicit owner consent for dormant history; never inherits another sign-in's delegation."
  def reauthorize(scope, session, id, handle) do
    with {:ok, thread} <- owned(scope, id),
         :ok <- delegation(session, scope.user_id),
         {:ok, fresh} <- Scope.load(session, handle),
         true <- fresh.user_id == thread.owner_id and fresh.account_id == thread.account_id,
         :ok <- authorize(fresh) do
      transact(fn ->
        thread = lock(thread.id)
        require_access!(fresh, thread)
        # Consent to a future turn cannot retroactively authorize historical
        # queued commands whose original human delegation was not imported.
        require_idle!(thread)
        history(update!(thread, %{owner_session_id: session.id, account_handle: handle}), fresh)
      end)
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  def ship_preview(scope, id, opts \\ []) do
    with {:ok, thread} <- owned(scope, id),
         {:ok, preview} <- shipping(opts).preview(scope, thread) do
      transact(fn ->
        fresh = lock(thread.id)
        require_access!(scope, fresh)
        require_idle!(fresh)
        binding = Map.take(fresh, [:account_id, :repository, :sandbox_id, :base_sha])

        if Map.take(preview, Map.keys(binding)) != binding or preview.thread_id != fresh.id or
             preview.mode != fresh.ship_mode or preview.target_branch != ship_target(fresh),
           do: Repo.rollback(:shipping_review_stale)

        Repo.insert!(struct!(Approval, Map.delete(preview, :actor)), log: false)
        Map.update!(preview, :mode, &to_string/1)
      end)
    end
  end

  def ship(scope, session, id, attrs) do
    with {:ok, thread} <- owned(scope, id),
         :ok <- delegation(session, scope.user_id),
         {:ok, request_id} <- uuid(attrs["request_id"]) do
      transact(fn ->
        thread = lock(thread.id)
        require_access!(scope, thread)

        approval =
          Repo.one(
            from a in Approval,
              where: a.thread_id == ^thread.id and a.request_id == ^request_id,
              lock: "FOR UPDATE"
          )

        if is_nil(approval) or approval.head_sha != attrs["head_sha"] or
             approval.base_sha != attrs["base_sha"] or
             approval.target_branch != attrs["target_branch"] or
             to_string(approval.mode) != attrs["mode"],
           do: Repo.rollback(:shipping_approval_invalid)

        if approval.status == :pending, do: require_idle!(thread)

        if approval.status == :pending and
             (approval.base_sha != thread.base_sha or approval.sandbox_id != thread.sandbox_id or
                approval.repository != thread.repository or approval.mode != thread.ship_mode or
                approval.target_branch != ship_target(thread)),
           do: Repo.rollback(:shipping_review_stale)

        if approval.status == :pending do
          require_delegation!(Sessions.get_by_id(thread.owner_session_id), thread.owner_id)

          approval =
            Repo.update!(
              Changeset.change(approval,
                status: :approved,
                approved_by_id: scope.user_id,
                approved_at: now()
              ),
              log: false
            )

          # The approval's originating human delegation is durable, not whichever
          # session happens to belong to this owner when a worker starts later.
          message =
            append!(thread, %{
              kind: "human",
              body: "Ship the reviewed changes.",
              author_id: scope.user_id,
              author_session_id: session.id,
              decision: %{"approval_id" => approval.id}
            })

          run =
            Repo.insert!(
              %Run{
                thread_id: thread.id,
                message_id: message.id,
                approval_id: approval.id,
                kind: "ship",
                heartbeat_at: now()
              },
              log: false
            )

          Lease.want(thread.id, "thread")
          insert_ship_job!(run)
          update!(Repo.reload!(thread), %{agent_status: "shipping"})
        end

        history(Repo.reload!(thread), scope)
      end)
    end
  end

  def reconcile_ship(scope, session, id, attrs, opts \\ []) do
    with {:ok, thread} <- owned(scope, id),
         :ok <- delegation(session, scope.user_id),
         {:ok, request_id} <- uuid(attrs["request_id"]),
         %Approval{} = approval <-
           Repo.get_by(Approval, thread_id: thread.id, request_id: request_id),
         %Run{status: status} = run <- Repo.get_by(Run, approval_id: approval.id),
         true <- status in ["outcome_unknown", "succeeded"],
         :ok <- runtime_access(thread, run),
         {:ok, result} <- shipping(opts).reconcile(thread, approval) do
      transact(fn ->
        thread = lock(thread.id)
        require_access!(scope, thread)
        fresh = Repo.one!(from r in Run, where: r.id == ^run.id, lock: "FOR UPDATE")
        if fresh.status not in ["outcome_unknown", "succeeded"], do: Repo.rollback(:stale_run)
        if not ship_result?(approval, result), do: Repo.rollback(:shipping_uncertain)

        if fresh.status != "succeeded" do
          ship_success!(thread, fresh, approval)

          append!(Repo.reload!(thread), %{
            kind: "notice",
            body:
              "GitHub confirms the exact reviewed changes were shipped. Publication was not repeated."
          })
        end

        history(Repo.reload!(thread), scope)
      end)
    else
      nil -> {:error, :not_found}
      false -> {:error, :stale_run}
      error -> error
    end
  end

  defp shipping(opts), do: Keyword.get(opts, :shipping, Shipping)
  defp ship_target(%{ship_mode: :direct} = thread), do: thread.base_branch
  defp ship_target(thread), do: thread.branch

  defp require_idle!(thread) do
    if thread.status != :active, do: Repo.rollback(:archived)

    if Repo.exists?(from r in Run, where: r.thread_id == ^thread.id and r.status in @unfinished),
      do: Repo.rollback(:busy)

    if thread.agent_status == "outcome_unknown" or
         Repo.exists?(
           from r in Run, where: r.thread_id == ^thread.id and r.status == "outcome_unknown"
         ),
       do: Repo.rollback(:shipping_uncertain)

    if Repo.exists?(
         from c in ToolCall,
           join: r in Run,
           on: r.id == c.run_id,
           where: r.thread_id == ^thread.id and c.status == "executing"
       ),
       do: Repo.rollback(:tool_outcome_unknown)
  end

  defp insert_ship_job!(run), do: %{"run_id" => run.id} |> ShipWorker.new() |> Oban.insert!()

  @doc "Claims Ship once under a live local lease. Running attempts are never dispatched again."
  def claim_ship(id, epoch) do
    transact(fn ->
      candidate = Repo.get!(Run, id)
      thread = lock(candidate.thread_id)
      run = Repo.one!(from r in Run, where: r.id == ^id, lock: "FOR UPDATE")
      if run.kind != "ship" or not lease_held?(thread.id, epoch), do: Repo.rollback(:stale_run)

      cond do
        run.status == "running" and epoch <= run.attempt ->
          Repo.rollback(:stale_run)

        run.status == "running" ->
          ship_uncertain!(thread, run)
          :reconcile_only

        run.status != "queued" ->
          :done

        true ->
          authority = runtime_access(thread, run)
          if authority == {:error, :tuist_unavailable}, do: Repo.rollback(:tuist_unavailable)
          if not lease_held?(thread.id, epoch), do: Repo.rollback(:stale_run)
          approval = Repo.get!(Approval, run.approval_id)

          if authority != :ok or thread.status != :active or approval.status != :approved or
               approval.approved_by_id != thread.owner_id do
            Repo.update!(Changeset.change(run, status: "failed"), log: false)
            Repo.update!(Changeset.change(approval, status: :failed), log: false)
            update!(thread, %{agent_status: "failed"})
            :done
          else
            approval = Repo.update!(Changeset.change(approval, status: :executing), log: false)

            run =
              Repo.update!(
                Changeset.change(run,
                  status: "running",
                  attempt: epoch,
                  session_id: thread.id,
                  heartbeat_at: now()
                ),
                log: false
              )

            {run, thread, approval}
          end
      end
    end)
  end

  def execute_ship(run, opts \\ []) do
    thread = Repo.get!(Thread, run.thread_id)
    approval = Repo.get!(Approval, run.approval_id)

    if owns_run?(run.id, run.attempt) do
      result = shipping(opts).execute(thread, approval, Repo.get!(Run, run.id))
      finish_ship(run, result)
    else
      {:error, :stale_run}
    end
  end

  def finish_ship(run, result) do
    with_attempt(run, fn thread, fresh ->
      approval = Repo.get!(Approval, fresh.approval_id)

      cond do
        match?({:ok, _}, result) and ship_result?(approval, elem(result, 1)) ->
          ship_success!(thread, fresh, approval)

          append!(Repo.reload!(thread), %{
            kind: "notice",
            body:
              "Shipped the reviewed changes using the GitHub App. No deployment was triggered by Luft."
          })

        result in Enum.map(
          [
            :shipping_review_stale,
            :shipping_export_failed,
            :shipping_snapshot_failed,
            :shipping_objects_invalid,
            :shipping_review_unavailable,
            :shipping_diff_empty_or_too_large,
            :workspace_busy,
            :workspace_unavailable,
            :repository_access_denied,
            :delegation_unavailable,
            :shipping_approval_invalid
          ],
          &{:error, &1}
        ) ->
          Repo.update!(Changeset.change(fresh, status: "failed", session_id: nil), log: false)
          Repo.update!(Changeset.change(approval, status: :failed), log: false)
          update!(thread, %{agent_status: "failed"})

          append!(Repo.reload!(thread), %{
            kind: "notice",
            body:
              "Ship did not publish: the workspace, repository or authorization changed. Review the current changes again before approving Ship."
          })

        true ->
          # After dispatch, every unconfirmed outcome is uncertain. An upstream
          # publication authorization may already be irrevocably committed.
          ship_uncertain!(thread, fresh)
      end

      Repo.reload!(thread)
    end)
  end

  def ship_interrupted(run, opts \\ []) do
    transact(fn ->
      thread = lock(run.thread_id)
      fresh = Repo.get!(Run, run.id)

      if fresh.status == "running" and fresh.attempt == run.attempt and
           (not Keyword.get(opts, :only_expired, false) or
              not lease_held?(thread.id, fresh.attempt)),
         do: ship_uncertain!(thread, fresh)

      :ok
    end)
  end

  defp ship_result?(approval, result) do
    is_map(result) and
      Map.take(result, [:request_id, :head_sha, :target_branch]) ==
        Map.take(approval, [:request_id, :head_sha, :target_branch])
  end

  defp ship_success!(thread, run, approval) do
    Repo.update!(Changeset.change(run, status: "succeeded", session_id: nil, checkpoint: nil),
      log: false
    )

    Repo.update!(Changeset.change(approval, status: :succeeded), log: false)

    update!(thread, %{
      base_sha: approval.head_sha,
      agent_status: "idle",
      snoozed_until_needed: false
    })
  end

  defp ship_uncertain!(thread, run) do
    Repo.update!(
      Changeset.change(run, status: "outcome_unknown", session_id: nil, checkpoint: nil),
      log: false
    )

    update!(thread, %{agent_status: "outcome_unknown", snoozed_until_needed: false})

    append!(Repo.reload!(thread), %{
      kind: "notice",
      body:
        "Ship could not confirm its result. Further changes are blocked until the reviewed destination is reconciled; publication is not automatically repeated."
    })
  end

  def snooze(scope, id, snooze) do
    with {:ok, attrs} <- snooze_attrs(snooze), {:ok, thread} <- owned(scope, id) do
      transact(fn ->
        thread = lock(thread.id)
        require_access!(scope, thread)

        if attrs.snoozed_until_needed and thread.agent_status not in @working,
          do: Repo.rollback(:not_working)

        thread = update!(thread, attrs)
        if thread.snoozed_until, do: SnoozeWorker.schedule!(thread)
        history(thread, scope)
      end)
    end
  end

  def wake_snoozed(id, %DateTime{} = until) do
    transact(fn ->
      case Repo.one(from t in Thread, where: t.id == ^id, lock: "FOR UPDATE") do
        %Thread{snoozed_until: ^until, status: :active} = thread ->
          thread = update!(thread, %{snoozed_until: nil})
          Notifications.notify_thread_finished(thread, "snooze_ended")
          :woken

        _ ->
          :ok
      end
    end)
  end

  def recover do
    # A queued job can be recreated, but a dispatched publication can only be
    # observed. Recovery never changes a running Ship back into queued work.
    from(r in Run,
      left_join: s in "agent_sessions",
      on: s.id == fragment("?::text", r.thread_id),
      where: r.kind == "ship" and r.status in ["queued", "running"],
      where: is_nil(s.lease_expires_at) or s.lease_expires_at < fragment("CURRENT_TIMESTAMP"),
      select: r,
      limit: 100
    )
    |> Repo.all()
    |> Enum.each(fn run ->
      if run.status == "queued" do
        Lease.want(run.thread_id, "thread", min_epoch: run.attempt)
        insert_ship_job!(run)
      else
        ship_interrupted(run, only_expired: true)
      end
    end)

    # Leases recover ordinary crashes themselves. Repair only missing/unwanted
    # hosts; imported histories without an explicit delegation stay dormant.
    from(r in Run,
      join: t in Thread,
      on: t.id == r.thread_id,
      left_join: s in "agent_sessions",
      on: s.id == fragment("?::text", t.id),
      where:
        t.status == :active and not is_nil(t.owner_session_id) and
          r.kind != "ship" and r.status in ["queued", "running"],
      where:
        is_nil(s.id) or
          (s.wanted == false and is_nil(s.deleted_at) and
             (is_nil(s.lease_expires_at) or s.lease_expires_at < fragment("CURRENT_TIMESTAMP"))),
      select: {t.id, r.attempt},
      limit: 100
    )
    |> Repo.all()
    |> Enum.each(fn {id, attempt} ->
      Lease.want(id, "thread", min_epoch: attempt)
      Lease.wake(id)
    end)

    :ok
  end

  def models(scope, session) do
    with :ok <- authorize(scope),
         :ok <- delegation(session, scope.user_id),
         do: Provider.models(session)
  end

  def repositories(scope, session, handle) do
    with :ok <- authorize(scope),
         :ok <- delegation(session, scope.user_id),
         {:ok, repositories} when is_list(repositories) <-
           Capabilities.request(
             %{
               owner_session_id: session.id,
               owner_id: scope.user_id,
               account_id: scope.account_id,
               account_handle: handle
             },
             "repositories",
             %{}
           ) do
      {:ok, repositories}
    else
      {:ok, _} -> {:error, :capability_unavailable}
      error -> error
    end
  end

  def snapshot(scope, :inbox) do
    with :ok <- authorize_reader(scope) do
      revision =
        Repo.one(
          from i in "thread_inboxes",
            where: i.account_id == ^scope.account_id and i.owner_id == ^scope.user_id,
            select: i.revision
        ) || 0

      {:ok, %{revision: revision, agent_status: "idle", activity: nil}}
    end
  end

  def snapshot(scope, id) do
    with {:ok, id} <- uuid(id),
         %Thread{} = thread <- Repo.get_by(Thread, id: id, account_id: scope.account_id),
         :ok <- access(scope, thread) do
      activity =
        Repo.one(
          from c in ToolCall,
            join: r in Run,
            on: r.id == c.run_id,
            join: m in Message,
            on: m.id == c.message_id,
            where:
              r.thread_id == ^thread.id and r.status == "running" and c.status == "executing",
            order_by: [desc: m.position],
            limit: 1,
            select: c.name
        )

      {:ok, %{revision: thread.revision, agent_status: thread.agent_status, activity: activity}}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @sync_page 200

  @doc """
  What changed in a thread since revision `since`, for a client that keeps it.
  Without a cursor, the latest page, as `get/3` returns it, replaces what the
  client has (`reset`), and so does it for a client too far behind for one
  delta. Otherwise the thread's fields and the messages whose version is
  above `since`; `:unchanged` when the thread's revision isn't. Rows the
  client already has may come again; applying them is idempotent.
  """
  def changes(scope, id, since) do
    with {:ok, id} <- uuid(id),
         %Thread{} = thread <- Repo.get_by(Thread, id: id, account_id: scope.account_id),
         :ok <- access(scope, thread) do
      rows =
        if since && thread.revision > since,
          do:
            Repo.all(
              from m in Message,
                where: m.thread_id == ^thread.id and m.version > ^since,
                order_by: m.position,
                limit: ^(@sync_page + 1)
            ),
          else: []

      cond do
        is_nil(since) or length(rows) > @sync_page ->
          {:ok, %{reset: true, cursor: thread.revision, thread: history(thread, scope)}}

        thread.revision <= since ->
          :unchanged

        true ->
          {:ok,
           %{
             reset: false,
             cursor: thread.revision,
             thread: people(%{thread | messages: rows}, scope)
           }}
      end
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc "Runtime compatibility: reads through the persisted owner's exact delegation."
  def history(thread) do
    with session when not is_nil(session) <- Sessions.get_by_id(thread.owner_session_id),
         true <- session.user_sub == to_string(thread.owner_id),
         {:ok, scope} <- Scope.load(session, thread.account_handle),
         :ok <- access(scope, thread) do
      history(thread, scope)
    else
      _ -> raise "Thread delegation is unavailable."
    end
  end

  def history(thread, scope, before \\ nil) do
    query = from m in Message, where: m.thread_id == ^thread.id
    query = if before, do: from(m in query, where: m.position < ^before), else: query

    rows =
      Repo.all(
        from m in query,
          order_by: [desc: m.position],
          limit: 51,
          select: %{id: m.id, bytes: fragment("octet_length(?::text)", m.attachments)}
      )

    {ids, _} =
      rows
      |> Enum.take(50)
      |> Enum.reduce_while({[], 0}, fn row, {ids, bytes} ->
        if bytes + row.bytes <= 6 * 1024 * 1024,
          do: {:cont, {[row.id | ids], bytes + row.bytes}},
          else: {:halt, {ids, bytes}}
      end)

    messages = Repo.all(from m in query, where: m.id in ^ids, order_by: m.position)
    more = length(rows) > length(messages)

    thread
    |> Map.merge(%{
      messages: messages,
      has_more: more,
      next_before: if(more and messages != [], do: hd(messages).position)
    })
    |> people(scope)
  end

  def serialize(thread) do
    %{
      id: thread.id,
      title: thread.title,
      goal: thread.goal,
      provider: thread.provider,
      model: thread.model,
      repository: thread.repository || "",
      runner_id: thread.runner_id,
      workspace_ready_id: nil,
      reauthorization_required:
        delegation(Sessions.get_by_id(thread.owner_session_id), thread.owner_id) != :ok,
      can_reauthorize: Map.get(thread, :can_reauthorize, false),
      branch: thread.branch || "",
      profile: "linux",
      status: thread.agent_status,
      visibility: "private",
      archive_status: to_string(thread.status),
      snoozed_until: thread.snoozed_until && DateTime.to_iso8601(thread.snoozed_until),
      snoozed_until_needed: thread.snoozed_until_needed,
      revision: thread.revision,
      has_more: thread.has_more,
      next_before: thread.next_before,
      diff: "",
      owner: person(thread, thread.owner_id),
      participants: Enum.map(thread.participant_ids, &person(thread, &1)),
      messages: Enum.map(thread.messages, &serialize_message(&1, thread.people))
    }
  end

  defp serialize_message(%Message{kind: "record"} = message, people) do
    message
    |> Map.put(:kind, "agent")
    |> serialize_message(people)
    |> Map.put(:record_reference, message.record_reference)
  end

  defp serialize_message(%Message{kind: kind} = message, people)
       when kind in ["decision", "card", "progress"] do
    base =
      serialize_message(
        %{message | kind: if(kind == "progress", do: "notice", else: "agent")},
        people
      )

    case kind do
      "progress" ->
        Map.put(base, :progress, message.progress)

      "card" ->
        Map.put(base, :ui, %{size: message.card_size, source: message.card_source})

      "decision" ->
        decision =
          Map.take(message.decision || %{}, ~w(question options allow_other status answer))

        base = Map.put(base, :decision, decision)

        if decision["status"] == "pending" and is_binary(message.card_source),
          do: Map.put(base, :ui, %{size: message.card_size, source: message.card_source}),
          else: base
    end
  end

  defp serialize_message(message, people) do
    value = %{
      id: message.id,
      role:
        case(message.kind,
          do: (
            "human" -> "user"
            "agent" -> "assistant"
            "tool" -> "tool"
            _ -> "system"
          )
        ),
      content: message.body || "",
      attachments: message.attachments,
      position: message.position,
      toolName: message.tool_name,
      toolStatus: message.tool_state,
      suggestions: message.suggestions,
      suggestion_icons: message.suggestion_icons || %{},
      author:
        if(message.kind == "human" and message.author_id,
          do: people[message.author_id] || %{id: message.author_id, handle: nil}
        ),
      createdAt: DateTime.to_iso8601(message.inserted_at)
    }

    # A client that queued this prompt offline recognizes it by its key.
    value =
      if message.kind == "human" and message.request_id,
        do: Map.put(value, :request_id, message.request_id),
        else: value

    if message.kind == "tool" and is_map(message.progress),
      do: Map.put(value, :build, message.progress),
      else: value
  end

  defp prompt!(thread, scope, session, body, files, request_id, attrs, opts) do
    if thread.status != :active, do: Repo.rollback(:archived)

    if Repo.exists?(
         from r in Run,
           where: r.thread_id == ^thread.id and r.kind == "ship" and r.status == "outcome_unknown"
       ),
       do: Repo.rollback(:shipping_uncertain)

    owner_session = Sessions.get_by_id(thread.owner_session_id)
    require_delegation!(owner_session, thread.owner_id)
    if is_nil(thread.account_handle), do: Repo.rollback(:execution_unavailable)

    admit!(
      opts,
      scope,
      owner_session,
      session,
      Map.take(thread, ~w(provider model repository base_branch runner_id account_handle)a)
    )

    case pending_question(thread, attrs["question_id"]) do
      nil ->
        if Map.has_key?(attrs, "question_id"), do: Repo.rollback(:question_answered)

        if Repo.exists?(
             from r in Run, where: r.thread_id == ^thread.id and r.status in @unfinished
           ),
           do: Repo.rollback(:busy)

        message = append!(thread, human(scope, session, body, files, request_id))
        loop_in!(thread, scope, body)
        enqueue!(thread, message.id)

      question ->
        answer!(thread, question, scope, session, body, files, request_id, attrs)
    end
  end

  defp pending_question(thread, nil) do
    Repo.one(
      from m in Message,
        where:
          m.thread_id == ^thread.id and m.kind == "decision" and
            fragment("?->>'status' = 'pending'", m.decision),
        order_by: [desc: m.position],
        limit: 1
    )
  end

  defp pending_question(thread, id) do
    with {:ok, id} <- uuid(id),
         %Message{kind: "decision", decision: %{"status" => "pending"}} = question <-
           Repo.get_by(Message, thread_id: thread.id, id: id) do
      question
    else
      _ -> Repo.rollback(:question_answered)
    end
  end

  defp answer!(thread, question, scope, session, body, files, request_id, attrs) do
    run =
      Repo.one(
        from r in Run,
          where: r.id == ^question.decision["run_id"] and r.thread_id == ^thread.id,
          lock: "FOR UPDATE"
      )

    if is_nil(run) or run.status != "waiting", do: Repo.rollback(:question_answered)
    cancelled = attrs["cancel"] == true

    option =
      Enum.find(question.decision["options"] || [], fn option ->
        if Map.has_key?(attrs, "option_id"),
          do: option["id"] == attrs["option_id"],
          else: body in [option["id"], option["label"]]
      end)

    if not cancelled and is_nil(option) and
         (Map.has_key?(attrs, "option_id") or not question.decision["allow_other"]),
       do: Repo.rollback(:invalid_arguments)

    answer =
      cond do
        cancelled -> nil
        option -> %{"option_id" => option["id"], "text" => option["label"]}
        true -> %{"option_id" => nil, "text" => body}
      end

    decision =
      Map.merge(question.decision, %{
        "status" => if(cancelled, do: "cancelled", else: "answered"),
        "answer" => answer,
        "answered_by_id" => scope.user_id
      })

    Repo.update!(Changeset.change(question, decision: decision), log: false)

    append!(
      thread,
      Map.put(
        human(scope, session, body, files, request_id),
        :decision,
        Map.take(attrs, ~w(question_id option_id cancel))
      )
    )

    Repo.update!(
      Changeset.change(run,
        status: "queued",
        waited_seconds: run.waited_seconds + max(DateTime.diff(now(), run.updated_at), 0),
        heartbeat_at: now()
      ),
      log: false
    )

    Lease.want(thread.id, "thread", min_epoch: run.attempt)

    update!(Repo.reload!(thread), %{
      agent_status: "queued",
      snoozed_until: nil,
      snoozed_until_needed: false
    })
  end

  @doc "Claims inference work only under a newer, live thread lease epoch."
  def claim(id, epoch) when is_integer(epoch) and epoch > 0 do
    result =
      transact(fn ->
        case Repo.get(Run, id) do
          nil ->
            Repo.rollback(:stale_run)

          candidate ->
            thread = lock(candidate.thread_id)
            run = Repo.one!(from r in Run, where: r.id == ^id, lock: "FOR UPDATE")

            if run.kind == "ship" or run.status not in ["queued", "running"] or
                 epoch <= run.attempt or not lease_held?(thread.id, epoch),
               do: Repo.rollback(:stale_run)

            authority = runtime_access(thread, run)
            if authority == {:error, :tuist_unavailable}, do: Repo.rollback(:tuist_unavailable)
            if not lease_held?(thread.id, epoch), do: Repo.rollback(:stale_run)

            cond do
              thread.status != :active or authority != :ok ->
                interrupt!(thread, run)
                :forbidden

              expired?(run) ->
                expire!(thread, run)
                :expired

              true ->
                fresh =
                  Repo.update!(
                    Changeset.change(run,
                      status: "running",
                      attempt: epoch,
                      session_id: thread.id,
                      heartbeat_at: now()
                    ),
                    log: false
                  )

                {fresh, update!(thread, %{agent_status: "running"})}
            end
        end
      end)

    case result do
      {:ok, reason} when reason in [:forbidden, :expired] -> {:error, reason}
      other -> other
    end
  end

  def claim(_, _), do: {:error, :stale_run}

  def next_run(thread_id) do
    Repo.one(
      from r in Run,
        where:
          r.thread_id == ^thread_id and r.kind != "ship" and r.status in ["queued", "running"],
        order_by: [asc: r.inserted_at, asc: r.id],
        select: r.id,
        limit: 1
    )
  end

  def owns_run?(id, attempt) do
    case Repo.get(Run, id) do
      %Run{attempt: ^attempt, status: "running"} = run ->
        thread = Repo.get(Thread, run.thread_id)

        not is_nil(thread) and thread.status == :active and runtime_access(thread, run) == :ok and
          lease_held?(thread.id, attempt)

      _ ->
        false
    end
  end

  def keep_alive(run) do
    Repo.update_all(
      from(r in Run,
        where:
          r.id == ^run.id and r.attempt == ^run.attempt and r.status == "running" and
            r.kind != "ship"
      ),
      [set: [heartbeat_at: now()]],
      log: false
    )

    :ok
  end

  def with_attempt(run, fun) do
    transact(fn ->
      thread = lock(run.thread_id)

      fresh =
        Repo.one(
          from r in Run, where: r.id == ^run.id and r.thread_id == ^thread.id, lock: "FOR UPDATE"
        )

      if is_nil(fresh) or not owns_run?(fresh.id, run.attempt), do: Repo.rollback(:stale_run)
      result = fun.(thread, fresh)
      if not lease_held?(thread.id, run.attempt), do: Repo.rollback(:stale_run)
      result
    end)
  end

  def request_repository(run, attrs) do
    thread = Repo.get!(Thread, run.thread_id)

    with name when is_binary(name) and name != "" <- attrs["repository"],
         {:ok, owner} <- Capabilities.owner(thread),
         {:ok, repository} <- Repository.authorize(owner, name),
         :ok <- Checkout.fits(repository),
         branch = attrs["base_branch"] || repository.default_branch,
         true <-
           is_binary(branch) and byte_size(branch) in 1..255 and
             Regex.match?(~r/\A[\w][\w.\/-]*\z/u, branch) and
             not String.contains?(branch, ["..", "//", "@{"]),
         {:ok, _head} <- Repository.branch_head(owner, repository.name, branch) do
      with_attempt(run, fn fresh, _ ->
        cond do
          fresh.repository == repository.name ->
            {:attached, fresh.repository, fresh.base_branch}

          not is_nil(fresh.repository) or not is_nil(fresh.runner_id) ->
            Repo.rollback(:repository_attached)

          true ->
            update!(fresh, %{
              repository: repository.name,
              base_branch: branch,
              branch: "threads/#{fresh.id}"
            })

            {:attached, repository.name, branch}
        end
      end)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_arguments}
    end
  end

  def rename(run, name) when is_binary(name) do
    if String.trim(name) != "" and String.length(name) <= 120 do
      with_attempt(run, fn thread, _ ->
        update!(thread, %{title: String.trim(name)})
        "Thread renamed."
      end)
    else
      {:error, :invalid_arguments}
    end
  end

  def rename(_, _), do: {:error, :invalid_arguments}

  def show_card(run, summary, size, source) do
    with_attempt(run, fn thread, _ ->
      since = Repo.get!(Message, run.message_id).position

      if not Repo.exists?(
           from m in Message,
             where:
               m.thread_id == ^thread.id and m.kind == "card" and m.position > ^since and
                 m.card_size == ^size and m.card_source == ^source
         ),
         do: append!(thread, %{kind: "card", body: summary, card_size: size, card_source: source})

      "The card is shown in the conversation above your reply. Don't repeat what it shows."
    end)
  end

  def show_record(run, reference) do
    with_attempt(run, fn thread, fresh ->
      result =
        Records.author(fresh, fn scope ->
          Records.check(scope, reference)
        end)

      if result != {:ok, :ok}, do: Repo.rollback(:forbidden)
      since = Repo.get!(Message, fresh.message_id).position

      unless Repo.exists?(
               from m in Message,
                 where:
                   m.thread_id == ^thread.id and m.kind == "record" and m.position > ^since and
                     m.record_reference == ^reference
             ) do
        append!(thread, %{kind: "record", body: "Open record", record_reference: reference})
      end

      "Record reference shown. Opening it checks the reader's current permissions and loads current data."
    end)
  end

  def user_question(run, request_id),
    do: Repo.get_by(Message, thread_id: run.thread_id, request_id: request_id)

  def ask_user(run, request_id, question, source) do
    with_attempt(run, fn thread, fresh ->
      case user_question(run, request_id) do
        %Message{} = message ->
          message

        nil ->
          summary =
            question["question"] <>
              "\n\n" <> Enum.map_join(question["options"], "\n", &"- #{&1["label"]}")

          message =
            append!(thread, %{
              kind: "decision",
              request_id: request_id,
              body: summary,
              card_size: "medium",
              card_source: source,
              decision: Map.merge(question, %{"run_id" => run.id, "status" => "pending"})
            })

          Repo.update!(Changeset.change(fresh, status: "waiting"), log: false)
          update!(Repo.reload!(thread), %{agent_status: "waiting", snoozed_until_needed: false})
          message
      end
    end)
  end

  def update_progress(run, steps) do
    with {:ok, steps} <- progress_steps(steps) do
      with_attempt(run, fn thread, _ ->
        since = Repo.get!(Message, run.message_id).position

        body =
          Enum.map_join(steps, "\n", fn
            %{"status" => "completed", "title" => title} ->
              "- [x] " <> title

            %{"status" => "in_progress", "title" => title} ->
              "- [ ] " <> title <> " (in progress)"

            %{"title" => title} ->
              "- [ ] " <> title
          end)

        attrs = %{body: body, progress: %{"steps" => steps}}

        case Repo.one(
               from m in Message,
                 where:
                   m.thread_id == ^thread.id and m.kind == "progress" and m.position > ^since,
                 order_by: [desc: m.position],
                 limit: 1
             ) do
          nil ->
            append!(thread, Map.put(attrs, :kind, "progress"))

          message ->
            Repo.update!(Changeset.change(message, attrs), log: false)
            update!(thread, %{})
        end

        "The person sees this plan, updated in place. Update it as each step starts and finishes; don't repeat it in your reply."
      end)
    end
  end

  def record_build_progress(run, invocation_id, snapshot)
      when is_binary(invocation_id) and is_map(snapshot) do
    with {:ok, progress} <- BuildProgress.normalize(snapshot),
         message_id when not is_nil(message_id) <-
           Repo.one(
             from c in ToolCall,
               where:
                 c.run_id == ^run.id and c.invocation_id == ^invocation_id and
                   c.status == "executing",
               select: c.message_id,
               limit: 1
           ),
         %Message{tool_state: "running"} = message <- Repo.get(Message, message_id),
         true <- BuildProgress.due?(message, progress) do
      _ =
        with_attempt(run, fn thread, _ ->
          with %Message{tool_state: "running"} = message <- Repo.get(Message, message_id),
               true <- BuildProgress.due?(message, progress) do
            Repo.update!(
              Changeset.change(message, progress: progress, body: BuildProgress.body(progress)),
              log: false
            )

            update!(thread, %{})
          end
        end)
    end

    :ok
  end

  def record_build_progress(_, _, _), do: :ok

  def begin_tool_call(run, call_id, name, args, tools) do
    key = fingerprint({:session_call, call_id, name, args})

    case with_attempt(run, fn thread, _ ->
           reserve_tool!(run, thread, key, name, {:session, tools, call_id})
         end) do
      {:ok, {:dispatch, _}} ->
        :ok

      {:ok, {:replay, result}} ->
        {:block, "This tool call already ran. Its result was:\n\n" <> result}

      {:error, :tool_outcome_unknown} ->
        {:block, "An earlier tool call's outcome is unknown, so this call did not run."}

      {:error, _} ->
        {:block, "This run no longer owns the thread."}
    end
  end

  def complete_tool_call(run, call_id, name, args, result) do
    key = fingerprint({:session_call, call_id, name, args})

    case Repo.get_by(ToolCall, run_id: run.id, fingerprint: key, status: "executing") do
      nil -> :ok
      call -> with {:ok, _} <- complete_tool!(run, call, tool_output(result)), do: :ok
    end
  end

  def cancel_tool_calls(run, names) do
    with_attempt(run, fn _thread, _ ->
      for call <-
            Repo.all(
              from c in ToolCall,
                where: c.run_id == ^run.id and c.status == "executing" and c.name in ^names
            ) do
        complete_tool!(
          run,
          call,
          "Cancelled: the run ended before this call finished, so it may have partly run."
        )
      end
    end)
  end

  def record_notice(run, body) do
    with_attempt(run, fn thread, _ ->
      append!(thread, %{kind: "notice", body: body})
      :ok
    end)
  end

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
  Runs an external tool's effect at most once. `attrs` are stored on the call,
  such as the MCP server it reached, so it can be traced after that server is
  removed.
  """
  def call_external_tool(run, invocation_id, name, args, dispatch, attrs \\ %{}) do
    Repo.checkout(
      fn ->
        key = "thread-effects:#{run.thread_id}"

        case Repo.query!("SELECT pg_try_advisory_lock(hashtextextended($1, 0))", [key],
               log: false
             ).rows do
          [[true]] ->
            try do
              case with_attempt(run, fn thread, _ ->
                     reserve_tool!(
                       run,
                       thread,
                       fingerprint({invocation_id, name, args}),
                       name,
                       :thread,
                       attrs
                     )
                   end) do
                {:ok, {:replay, result}} ->
                  {:ok, result}

                {:ok, {:dispatch, call}} ->
                  case dispatch.() do
                    {:ok, output} when is_binary(output) ->
                      complete_tool!(run, call, output)

                    {:error, :invalid_arguments} ->
                      complete_tool!(run, call, "Tool failed: invalid_arguments")

                    _ ->
                      {:error, :tool_outcome_unknown}
                  end

                error ->
                  error
              end
            after
              Repo.query!("SELECT pg_advisory_unlock(hashtextextended($1, 0))", [key], log: false)
            end

          _ ->
            {:error, :workspace_busy}
        end
      end,
      timeout: :infinity
    )
  end

  def abandon(run), do: with_attempt(run, fn thread, fresh -> interrupt!(thread, fresh) end)

  def finish(%Run{kind: "ship"} = run, result), do: finish_ship(run, result)

  def finish(run, result) do
    with_attempt(run, fn thread, fresh ->
      unknown =
        Repo.exists?(from c in ToolCall, where: c.run_id == ^run.id and c.status == "executing")

      {status, body, suggestions, icons} =
        cond do
          unknown ->
            {"outcome_unknown",
             "A tool was interrupted. Its effects are unknown; further workspace changes are blocked.",
             [], %{}}

          match?({:ok, text} when is_binary(text), result) ->
            {:ok, text} = result
            {reply, suggestions, icons} = Agent.decode_reply(text)
            {"idle", reply, suggestions, icons}

          true ->
            {"failed",
             "The run could not complete. Check the connected AI account, then send a new message to retry.",
             [], %{}}
        end

      Repo.update!(
        Changeset.change(fresh,
          status: if(status == "idle", do: "succeeded", else: status),
          checkpoint: nil,
          session_id: nil
        ),
        log: false
      )

      append!(thread, %{
        kind: if(status == "idle", do: "agent", else: "notice"),
        body: body,
        suggestions: suggestions,
        suggestion_icons: icons
      })

      update!(Repo.reload!(thread), %{agent_status: status, snoozed_until_needed: false})
    end)
  end

  defp lease_held?(id, epoch) do
    Repo.exists?(
      from s in "agent_sessions",
        where:
          s.id == ^to_string(id) and s.epoch == ^epoch and is_nil(s.deleted_at) and
            s.lease_expires_at > fragment("CURRENT_TIMESTAMP")
    )
  end

  defp runtime_access(thread, run) do
    with true <- is_binary(thread.account_handle),
         owner when not is_nil(owner) <- Sessions.get_by_id(thread.owner_session_id),
         true <- owner.user_sub == to_string(thread.owner_id),
         {:ok, scope} <- Scope.load(owner, thread.account_handle),
         true <-
           scope.account_id == thread.account_id and scope.user_id == thread.owner_id and
             scope.can_create_threads,
         %Message{} = message <- Repo.get(Message, run.message_id),
         author when not is_nil(author) <- Sessions.get_by_id(message.author_session_id),
         true <- author.user_sub == to_string(message.author_id),
         {:ok, author_scope} <- Scope.load(author, thread.account_handle),
         :ok <- access(author_scope, thread) do
      :ok
    else
      {:error, :tuist_unavailable} -> {:error, :tuist_unavailable}
      _ -> {:error, :forbidden}
    end
  end

  defp expired?(run) do
    Repo.exists?(
      from r in Run,
        where:
          r.id == ^run.id and
            r.inserted_at <
              fragment(
                "CURRENT_TIMESTAMP - make_interval(hours => 3, secs => ?)",
                r.waited_seconds
              )
    )
  end

  defp expire!(thread, run) do
    unknown =
      Repo.exists?(from c in ToolCall, where: c.run_id == ^run.id and c.status == "executing")

    status = if unknown, do: "outcome_unknown", else: "failed"
    Repo.update!(Changeset.change(run, status: status, session_id: nil), log: false)
    update!(thread, %{agent_status: status})

    append!(thread, %{
      kind: "notice",
      body:
        "This run did not finish within 3 hours, so it was stopped. Unknown tool effects are never automatically repeated. Send a new message to continue."
    })
  end

  defp interrupt!(thread, run) do
    unknown =
      Repo.exists?(from c in ToolCall, where: c.run_id == ^run.id and c.status == "executing")

    status = if unknown or run.kind == "ship", do: "outcome_unknown", else: "interrupted"
    Repo.update!(Changeset.change(run, status: status, session_id: nil), log: false)
    update!(thread, %{agent_status: status, snoozed_until_needed: false})

    append!(thread, %{
      kind: "notice",
      body: "Execution was interrupted. Unknown tool effects are never automatically repeated."
    })
  end

  defp reserve_tool!(run, thread, key, name, scope, attrs \\ %{}) do
    case Repo.get_by(ToolCall, run_id: run.id, fingerprint: key) do
      %ToolCall{status: "completed", result: result} ->
        {:replay, result}

      %ToolCall{} = call when is_tuple(scope) ->
        {:dispatch, call}

      %ToolCall{} ->
        Repo.rollback(:tool_outcome_unknown)

      nil ->
        executing =
          from c in ToolCall,
            join: r in Run,
            on: r.id == c.run_id,
            where: r.thread_id == ^thread.id and c.status == "executing"

        executing =
          case scope do
            :thread ->
              executing

            {:session, tools, _} ->
              where(executing, [c], c.run_id != ^run.id or c.name not in ^tools)
          end

        if Repo.exists?(executing), do: Repo.rollback(:tool_outcome_unknown)

        message =
          append!(thread, %{
            kind: "tool",
            body: "Working…",
            tool_name: name,
            tool_state: "running"
          })

        invocation_id =
          case scope do
            {:session, _, call_id} -> call_id
            _ -> nil
          end

        call =
          Repo.insert!(
            struct!(
              %ToolCall{
                run_id: run.id,
                message_id: message.id,
                fingerprint: key,
                name: name,
                invocation_id: invocation_id
              },
              attrs
            ),
            log: false
          )

        {:dispatch, call}
    end
  end

  defp complete_tool!(run, call, output) do
    with_attempt(run, fn thread, _ ->
      fresh = Repo.get!(ToolCall, call.id)

      if fresh.status == "executing" do
        Repo.update!(Changeset.change(fresh, status: "completed", result: output), log: false)
        message = Repo.get!(Message, fresh.message_id)

        Repo.update!(
          Changeset.change(message, body: String.slice(output, 0, 8000), tool_state: "complete"),
          log: false
        )

        update!(thread, %{})
      end

      fresh.result || output
    end)
  end

  defp tool_output({:ok, text}) when is_binary(text), do: text
  defp tool_output({:ok, value}), do: inspect(value)
  defp tool_output({:error, reason}) when is_binary(reason), do: "Tool failed: " <> reason
  defp tool_output({:error, reason}), do: "Tool failed: " <> inspect(reason)

  defp progress_steps(steps) when is_list(steps) and steps != [] and length(steps) <= 20 do
    Enum.reduce_while(steps, {:ok, []}, fn
      %{"title" => title, "status" => status}, {:ok, acc}
      when is_binary(title) and status in ["pending", "in_progress", "completed"] ->
        title = String.trim(title)

        if title != "" and String.length(title) <= 120,
          do: {:cont, {:ok, acc ++ [%{"title" => title, "status" => status}]}},
          else: {:halt, {:error, :invalid_arguments}}

      _, _ ->
        {:halt, {:error, :invalid_arguments}}
    end)
  end

  defp progress_steps(_), do: {:error, :invalid_arguments}

  defp access(scope, thread) do
    cond do
      scope.account_id != thread.account_id ->
        {:error, :not_found}

      scope.user_id == thread.owner_id ->
        authorize(scope)

      is_nil(scope.organization_id) ->
        {:error, :not_found}

      Repo.exists?(
        from p in Participant, where: p.thread_id == ^thread.id and p.user_id == ^scope.user_id
      ) ->
        :ok

      true ->
        {:error, :not_found}
    end
  end

  defp owned(scope, id) do
    with {:ok, thread} <- get(scope, id) do
      if thread.owner_id == scope.user_id, do: {:ok, thread}, else: {:error, :forbidden}
    end
  end

  defp require_access!(scope, thread) do
    case access(scope, thread) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp delegation(%Session{id: id}, user_id) do
    case Sessions.get_by_id(id) do
      %Session{user_sub: sub} ->
        if sub == to_string(user_id), do: :ok, else: {:error, :unauthorized}

      _ ->
        {:error, :unauthorized}
    end
  end

  defp delegation(_, _), do: {:error, :unauthorized}

  defp require_delegation!(session, user_id) do
    case delegation(session, user_id) do
      :ok -> :ok
      _ -> Repo.rollback(:delegation_required)
    end
  end

  defp admit!(opts, scope, owner, author, selection) do
    adapter = Keyword.get(opts, :execution)

    if is_nil(adapter) or not Code.ensure_loaded?(adapter) or
         not function_exported?(adapter, :admit, 4),
       do: Repo.rollback(:execution_unavailable)

    case adapter.admit(scope, owner, author, selection) do
      :ok ->
        selection

      {:ok, normalized} when is_map(normalized) ->
        case selection(Map.new(normalized, fn {key, value} -> {to_string(key), value} end)) do
          {:ok, normalized} -> Map.put(normalized, :account_handle, selection.account_handle)
          {:error, reason} -> Repo.rollback(reason)
        end

      {:error, reason} ->
        Repo.rollback(reason)

      _ ->
        Repo.rollback(:execution_unavailable)
    end
  end

  defp people(thread, scope) do
    ids =
      Repo.all(
        from p in Participant,
          where: p.thread_id == ^thread.id,
          order_by: [p.inserted_at, p.user_id],
          select: p.user_id
      )

    %{
      thread
      | participant_ids: ids,
        people: Map.new(scope.people, &{&1.id, %{id: &1.id, handle: &1.handle}})
    }
    |> Map.put(
      :can_reauthorize,
      scope.user_id == thread.owner_id and thread.status == :active and scope.can_create_threads
    )
  end

  defp person(thread, id), do: thread.people[id] || %{id: id, handle: nil}

  defp loop_in!(thread, %{organization_id: nil}, _body), do: thread

  defp loop_in!(thread, scope, body) do
    handles = mentions(body)

    rows =
      scope.people
      |> Enum.filter(
        &(&1.active and &1.id != thread.owner_id and String.downcase(&1.handle) in handles)
      )
      |> Enum.map(
        &%{
          thread_id: thread.id,
          user_id: &1.id,
          added_by_id: scope.user_id,
          inserted_at: now(),
          updated_at: now()
        }
      )

    Repo.insert_all(Participant, rows,
      on_conflict: :nothing,
      conflict_target: [:thread_id, :user_id]
    )
  end

  defp human(scope, session, body, files, request_id),
    do: %{
      kind: "human",
      body: body,
      attachments: files,
      request_id: request_id,
      author_id: scope.user_id,
      author_session_id: session.id
    }

  defp lock(id), do: Repo.one!(from t in Thread, where: t.id == ^id, lock: "FOR UPDATE")

  defp append!(thread, attrs) do
    fresh = update!(Repo.reload!(thread), %{})

    Repo.insert!(
      struct!(Message, Map.merge(attrs, %{thread_id: fresh.id, position: fresh.revision})),
      log: false
    )
  end

  defp update!(thread, attrs) do
    previous_status = thread.agent_status

    thread =
      Repo.update!(
        Changeset.change(
          thread,
          Map.merge(attrs, %{revision: thread.revision + 1, updated_at: now()})
        ),
        log: false
      )

    Notifications.thread_changed(thread)

    if thread.status == :active and previous_status != thread.agent_status and
         thread.agent_status in ~w(idle waiting failed outcome_unknown interrupted) do
      status = if thread.agent_status == "interrupted", do: "failed", else: thread.agent_status
      Notifications.notify_thread_finished(thread, status)
    end

    readers =
      Enum.uniq([
        thread.owner_id
        | Repo.all(from p in Participant, where: p.thread_id == ^thread.id, select: p.user_id)
      ])

    Repo.insert_all(
      "thread_inboxes",
      Enum.map(readers, &%{owner_id: &1, account_id: thread.account_id, revision: 1}),
      conflict_target: [:owner_id, :account_id],
      on_conflict: from(i in "thread_inboxes", update: [inc: [revision: 1]])
    )

    topics = Enum.map(readers, &topic(&1, thread.account_id))

    Process.put(
      {__MODULE__, :changed},
      MapSet.union(Process.get({__MODULE__, :changed}, MapSet.new()), MapSet.new(topics))
    )

    thread
  end

  defp enqueue!(thread, message_id) do
    Repo.insert!(%Run{thread_id: thread.id, message_id: message_id, heartbeat_at: now()},
      log: false
    )

    Lease.want(thread.id, "thread")

    update!(Repo.reload!(thread), %{
      agent_status: "queued",
      snoozed_until: nil,
      snoozed_until_needed: false
    })
  end

  defp wake({: