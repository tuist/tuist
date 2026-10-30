defmodule Atlas.Automations do
  @moduledoc "Versioned, authorized automation definitions and durable execution admissions."

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Automations.Analytics
  alias Atlas.Automations.Approval
  alias Atlas.Automations.Attempt
  alias Atlas.Automations.Behavior
  alias Atlas.Automations.Catalog
  alias Atlas.Automations.Contract
  alias Atlas.Automations.DomainAccess
  alias Atlas.Automations.Event
  alias Atlas.Automations.ExecutionQuery
  alias Atlas.Automations.JavaScript
  alias Atlas.Automations.ListQuery
  alias Atlas.Automations.Observability
  alias Atlas.Automations.Plan
  alias Atlas.Automations.Resources
  alias Atlas.Automations.Revision
  alias Atlas.Automations.Run
  alias Atlas.Automations.Tracing
  alias Atlas.Automations.Trigger
  alias Atlas.Automations.Workers.ExecuteRun
  alias Atlas.Automations.Workflow
  alias Atlas.Repo
  alias Atlas.Users
  alias Oban.Cron.Expression

  def authorize(actor, action) when action in [:read, :write] do
    if Users.has_scope?(actor, "automation:#{action}"), do: :ok, else: {:error, :forbidden}
  end

  def list_workflows(actor, params \\ %{}),
    do: list(ListQuery.apply("workflows", params), actor, params, [:published_revision])

  def execution_analytics(actor, params \\ %{}), do: Analytics.get(actor, params)
  def list_behaviors(actor, params \\ %{}), do: list(ListQuery.apply("behaviors", params), actor, params)

  def list_runs(actor, params \\ %{}) do
    with {:ok, query} <- Analytics.runs_query(actor, params),
         do: list(ExecutionQuery.apply(query, params), actor, params, revision: :workflow)
  end

  def list_approvals(actor, params \\ %{}),
    do: list(ListQuery.apply("approvals", params), actor, params, [:reviewer, run: [revision: :workflow]])

  def list_triggers(actor, kind, params \\ %{}) when kind in ["schedule", "webhook"] do
    section = if kind == "schedule", do: "schedules", else: "webhooks"
    list(ListQuery.apply(section, params), actor, params, revision: :workflow)
  end

  def get_workflow(actor, id), do: get(Workflow, actor, id, [:published_revision])

  def get_run(actor, id),
    do:
      get(Run, actor, id, [
        :initiated_by,
        revision: :workflow,
        attempts: from(a in Attempt, order_by: [asc: a.inserted_at, asc: a.id])
      ])

  def execution_events(actor, id, params \\ %{}) do
    with {:ok, _} <- get(Run, actor, id) do
      list(from(e in Event, where: e.run_id == ^id, order_by: [desc: e.sequence]), actor, params)
    end
  end

  def execution_trace(actor, id, params \\ %{}) do
    with {:ok, run} <- get_run(actor, id),
         {:ok, {events, meta}} <- execution_events(actor, id, params) do
      {:ok,
       %{
         execution:
           Map.take(run, [
             :id,
             :revision_id,
             :trace_id,
             :span_id,
             :status,
             :trigger,
             :inserted_at,
             :completed_at,
             :trace_started_at,
             :trace_completed_at
           ]),
         spans:
           Enum.map(
             run.attempts,
             &Map.take(&1, [
               :id,
               :step_id,
               :status,
               :executor,
               :started_at,
               :completed_at,
               :duration_ms,
               :execution_duration_ms,
               :wait_started_at,
               :wait_duration_ms,
               :trace_id,
               :span_id,
               :parent_span_id,
               :job_id,
               :job_attempt,
               :diagnostic
             ])
           ),
         events:
           Enum.map(
             events,
             &Map.take(&1, [
               :id,
               :sequence,
               :event,
               :level,
               :message,
               :step_id,
               :attempt_id,
               :trace_id,
               :span_id,
               :metadata,
               :inserted_at
             ])
           ),
         pagination: Map.take(meta, [:current_page, :total_pages, :total_count])
       }}
    end
  end

  def create_workflow(actor, attrs, opts \\ []) do
    with :ok <- authorize(actor, :write),
         {:ok, workflow} <- %Workflow{created_by_id: actor.id} |> Workflow.changeset(attrs) |> Repo.insert() do
      audit(actor, "workflow.created", workflow, "workflows", opts)
      {:ok, workflow}
    end
  end

  def update_workflow(actor, id, attrs, opts \\ []) do
    Resources.update_workflow(actor, id, attrs, opts)
  end

  def save_workflow_version(actor, id, attrs, opts \\ []) do
    with :ok <- authorize(actor, :write),
         {:ok, workflow} <- version_base(actor, id),
         :ok <- check_version(workflow, opts),
         {:ok, candidate} <- workflow |> Workflow.changeset(attrs) |> Ecto.Changeset.apply_action(:insert),
         {:ok, plan} <- compile_workflow(candidate) do
      Repo.transaction(fn ->
        saved = save_version_definition!(actor, workflow, attrs, opts)
        revision = publish_revision!(actor, saved, plan, opts)
        %{saved | published_revision_id: revision.id, published_revision: revision}
      end)
    end
  end

  def validate_workflow(actor, id) do
    with :ok <- authorize(actor, :write), {:ok, workflow} <- get_workflow(actor, id), do: compile_workflow(workflow)
  end

  def publish_workflow(actor, id, opts \\ []) do
    with :ok <- authorize(actor, :write),
         {:ok, workflow} <- get_workflow(actor, id),
         {:ok, plan} <- compile_workflow(workflow) do
      Repo.transaction(fn ->
        locked = Repo.one(from(w in Workflow, where: w.id == ^id, lock: "FOR UPDATE")) || Repo.rollback(:not_found)

        if locked.updated_at != workflow.updated_at or locked.source != workflow.source or
             locked.input_schema != workflow.input_schema or locked.language != workflow.language do
          Repo.rollback(:draft_changed)
        end

        publish_revision!(actor, locked, plan, opts)
      end)
    end
  end

  def create_behavior(actor, attrs, opts \\ []) do
    with :ok <- authorize(actor, :write) do
      changeset = Behavior.changeset(%Behavior{created_by_id: actor.id}, Catalog.prepare_attributes(attrs))

      with {:ok, behavior} <- Ecto.Changeset.apply_action(changeset, :insert),
           {:ok, _snapshot} <- Catalog.snapshot(behavior),
           {:ok, saved} <- Repo.insert(changeset) do
        audit(actor, "behavior.created", saved, "behaviors", opts)
        {:ok, saved}
      end
    end
  end

  def run_workflow(actor, id, input, opts \\ []) do
    with :ok <- authorize(actor, :write),
         {:ok, workflow} <- get_workflow(actor, id),
         %Revision{} = revision <- published_revision(workflow) do
      admit(actor, revision, input, "manual", nil, opts)
    else
      nil -> {:error, :not_published}
      error -> error
    end
  end

  def admit(actor, revision, input, trigger, admission_key, opts \\ []) do
    with :ok <- authorize(actor, :write),
         :ok <- DomainAccess.authorize_execution(actor, revision.plan),
         :ok <- Contract.validate(revision.input_schema, input) do
      Tracing.span("automation.workflow.admit", fn ->
        Repo.transaction(fn ->
          ids = Tracing.ids()

          run =
            Repo.insert!(%Run{
              revision_id: revision.id,
              initiated_by_id: actor.id,
              input: input,
              trigger: trigger,
              admission_key: admission_key,
              trace_id: ids.trace_id,
              trace_flags: ids.trace_flags,
              span_id: ids.span_id,
              trace_started_at: DateTime.utc_now()
            })

          Tracing.admission(run)
          enqueue!(run.id)
          Observability.record!(run, "execution.queued", metadata: %{"actor_id" => actor.id})
          audit(actor, "execution.queued", run, "executions", opts)
          run
        end)
      end)
    end
  end

  def decide_approval(actor, id, decision, opts \\ []) when decision in ["approved", "rejected"] do
    with :ok <- authorize(actor, :write),
         {:ok, approval} <- get(Approval, actor, id) do
      Repo.transaction(fn ->
        run = Repo.one!(from(r in Run, where: r.id == ^approval.run_id, lock: "FOR UPDATE"))
        approval = Repo.get!(Approval, approval.id)

        if approval.reviewer_id != actor.id or approval.status != "pending" or run.status != "waiting_approval" do
          Repo.rollback(:decision_not_allowed)
        end

        updated =
          approval
          |> Ecto.Changeset.change(status: decision, decided_by_id: actor.id, decided_at: now())
          |> Repo.update!()

        attempts =
          Repo.all(
            from(a in Attempt,
              where: a.run_id == ^run.id and a.step_id == ^approval.step_id and a.status == "waiting_approval"
            )
          )

        Enum.each(attempts, &complete_approval_attempt!(&1, run, approval, decision, actor))

        if decision == "approved" do
          outputs = Map.put(run.outputs, approval.step_id, approval.payload)
          run |> Ecto.Changeset.change(status: "queued", cursor: run.cursor + 1, outputs: outputs) |> Repo.update!()
          enqueue!(run.id)
        else
          run
          |> Ecto.Changeset.change(status: "rejected", completed_at: now(), trace_completed_at: DateTime.utc_now())
          |> Repo.update!()
        end

        audit(actor, "approval.#{decision}", updated, "approvals", opts)
        updated
      end)
    end
  end

  defp complete_approval_attempt!(attempt, run, approval, decision, actor) do
    completed = Observability.complete!(attempt, decision, output: approval.payload)

    Tracing.with_run(
      run,
      "automation.approval.wait",
      fn _ ->
        Observability.record!(run, "approval.#{decision}",
          attempt: completed,
          metadata: %{
            "actor_id" => actor.id,
            "approval_id" => approval.id,
            "wait_duration_ms" => completed.wait_duration_ms
          }
        )
      end,
      Tracing.wait_options(attempt.wait_started_at)
    )
  end

  def control_run(actor, id, action, opts \\ []) when action in ["retry", "cancel"] do
    with :ok <- authorize(actor, :write),
         {:ok, _run} <- get_run(actor, id) do
      Repo.transaction(fn ->
        run = Repo.one!(from(r in Run, where: r.id == ^id, lock: "FOR UPDATE"))
        if run.initiated_by_id != actor.id, do: Repo.rollback(:forbidden)

        case {action, run.status} do
          {"retry", "failed"} ->
            updated =
              run
              |> Ecto.Changeset.change(status: "queued", last_error: nil, completed_at: nil, trace_completed_at: nil)
              |> Repo.update!()

            enqueue!(id)
            Observability.record!(updated, "execution.retried", metadata: %{"actor_id" => actor.id})
            audit(actor, "execution.retried", updated, "executions", opts)
            updated

          {"cancel", status} when status in ["queued", "running", "waiting_approval"] ->
            from(a in Approval, where: a.run_id == ^id and a.status == "pending")
            |> Repo.update_all(set: [status: "cancelled", updated_at: now()])

            from(a in Attempt, where: a.run_id == ^id and a.status in ["waiting_approval", "running"])
            |> Repo.all()
            |> Enum.each(&Observability.complete!(&1, "cancelled"))

            updated =
              run
              |> Ecto.Changeset.change(status: "cancelled", completed_at: now(), trace_completed_at: DateTime.utc_now())
              |> Repo.update!()

            Observability.record!(updated, "execution.cancelled", metadata: %{"actor_id" => actor.id})
            audit(actor, "execution.cancelled", updated, "executions", opts)
            updated

          _ ->
            Repo.rollback(:invalid_execution_state)
        end
      end)
    end
  end

  def create_trigger(actor, workflow_id, attrs, opts \\ []) do
    with :ok <- authorize(actor, :write),
         {:ok, workflow} <- get_workflow(actor, workflow_id),
         %Revision{} = revision <- published_revision(workflow) do
      changeset = Trigger.changeset(%Trigger{revision_id: revision.id, execution_user_id: actor.id}, attrs)

      with {:ok, trigger} <- Ecto.Changeset.apply_action(changeset, :insert),
           :ok <- validate_trigger_input(trigger, revision) do
        secret = if trigger.kind == "webhook", do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
        next = if trigger.kind == "schedule", do: trigger.cron |> Expression.parse!() |> Expression.next_at()

        changeset =
          Ecto.Changeset.change(changeset, token_hash: secret && :crypto.hash(:sha256, secret), next_run_at: next)

        with {:ok, saved} <- Repo.insert(changeset) do
          audit(actor, "trigger.created", saved, trigger_section(saved), opts)
          {:ok, %{trigger: saved, secret: secret}}
        end
      end
    else
      nil -> {:error, :not_published}
      error -> error
    end
  end

  def set_trigger_enabled(actor, id, enabled, opts \\ []) when is_boolean(enabled) do
    Resources.update_trigger(actor, id, %{"enabled" => enabled}, opts)
  end

  def webhook(id, secret, delivery_id, input) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         true <- is_binary(secret) and byte_size(secret) <= 256,
         true <- is_binary(delivery_id) and byte_size(delivery_id) in 1..128 do
      webhook_locked(id, secret, delivery_id, input)
    else
      _ -> {:error, :unauthorized}
    end
  end

  def schedule_due do
    ids =
      Repo.all(
        from(t in Trigger,
          where: t.kind == "schedule" and t.enabled and t.next_run_at <= ^now(),
          select: t.id,
          limit: 100
        )
      )

    Enum.each(ids, &schedule_one/1)
    :ok
  end

  def enqueue!(id) do
    %{"run_id" => id} |> ExecuteRun.new() |> Repo.insert!()
  end

  def audit(actor, action, resource, section, opts \\ []) do
    Audit.record(
      "automation.#{action}",
      %{
        target_type: "automation_#{section}",
        target_id: resource.id,
        target_label: Map.get(resource, :name) || resource.id,
        metadata: Map.merge(%{"path" => resource_path(section, resource.id)}, Keyword.get(opts, :metadata, %{}))
      },
      actor: actor,
      interface: Keyword.get(opts, :interface, "dashboard")
    )
  end

  def now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp resource_path(section, id) when section in ["workflows", "executions"], do: "/automation/#{section}/#{id}"
  defp resource_path(section, _id), do: "/automation/#{section}"

  defp list(query, actor, params, preload \\ []) do
    with :ok <- authorize(actor, :read) do
      page =
        case Integer.parse(to_string(params["page"] || "1")) do
          {page, ""} when page > 0 and page <= 100_000 -> page
          _ -> 1
        end

      {items, meta} =
        query
        |> DomainAccess.scope(actor)
        |> default_order()
        |> Flop.run(%Flop{page: page, page_size: 20}, repo: Repo)

      {:ok, {Repo.preload(items, preload), meta}}
    end
  end

  defp default_order(%{order_bys: []} = query), do: order_by(query, desc: :inserted_at, desc: :id)
  defp default_order(query), do: query

  defp get(schema, actor, id, preload \\ []) do
    with :ok <- authorize(actor, :read),
         {:ok, _} <- Ecto.UUID.cast(id),
         resource when not is_nil(resource) <- Repo.get(DomainAccess.scope(schema, actor), id) do
      {:ok, Repo.preload(resource, preload)}
    else
      {:error, :forbidden} = error -> error
      _ -> {:error, :not_found}
    end
  end

  defp version_base(actor, nil), do: {:ok, %Workflow{created_by_id: actor.id}}
  defp version_base(actor, id), do: get_workflow(actor, id)

  defp check_version(workflow, opts) do
    case Keyword.fetch(opts, :expected_revision_id) do
      {:ok, expected} when expected != workflow.published_revision_id -> {:error, :workflow_changed}
      _ -> :ok
    end
  end

  defp save_version_definition!(actor, %{id: nil} = workflow, attrs, opts) do
    saved = workflow |> Workflow.changeset(attrs) |> Repo.insert!()
    audit(actor, "workflow.created", saved, "workflows", opts)
    saved
  end

  defp save_version_definition!(actor, workflow, attrs, opts) do
    locked = Repo.one(from(w in Workflow, where: w.id == ^workflow.id, lock: "FOR UPDATE")) || Repo.rollback(:not_found)
    fields = [:name, :description, :source, :language, :input_schema, :published_revision_id, :updated_at]
    if Map.take(locked, fields) != Map.take(workflow, fields), do: Repo.rollback(:workflow_changed)
    saved = locked |> Workflow.changeset(attrs) |> Repo.update!()
    audit(actor, "workflow.updated", saved, "workflows", opts)
    saved
  end

  defp publish_revision!(actor, workflow, plan, opts) do
    number = (Repo.aggregate(from(r in Revision, where: r.workflow_id == ^workflow.id), :max, :number) || 0) + 1

    revision =
      Repo.insert!(%Revision{
        workflow_id: workflow.id,
        published_by_id: actor.id,
        number: number,
        plan: plan,
        source: workflow.source,
        language: workflow.language,
        input_schema: workflow.input_schema
      })

    workflow |> Ecto.Changeset.change(published_revision_id: revision.id) |> Repo.update!()

    audit(
      actor,
      "workflow.published",
      workflow,
      "workflows",
      Keyword.put(opts, :metadata, %{"revision_id" => revision.id, "number" => number})
    )

    revision
  end

  defp compile_workflow(workflow) do
    with :ok <- Contract.validate_schema(workflow.input_schema),
         {:ok, raw} <- decode_source(workflow),
         :ok <- Contract.validate(%{"type" => "object"}, raw),
         {:ok, plan} <- Plan.compile(raw),
         true <- Contract.within_budget?(plan, 262_144) do
      {:ok, plan}
    else
      false -> {:error, "Published plans must fit within 256 KiB."}
      {:error, _} = error -> error
    end
  end

  defp decode_source(%{language: "json", source: source}) do
    case JSON.decode(source) do
      {:ok, plan} -> {:ok, plan}
      _ -> {:error, "Invalid JSON plan."}
    end
  end

  defp decode_source(%{language: "javascript", source: source}), do: JavaScript.evaluate(source, %{})

  defp published_revision(%{published_revision_id: nil}), do: nil
  defp published_revision(workflow), do: Repo.get(Revision, workflow.published_revision_id)

  defp validate_trigger_input(%{kind: "schedule", input: input}, revision),
    do: Contract.validate(revision.input_schema, input)

  defp validate_trigger_input(_, _), do: :ok

  defp webhook_locked(id, secret, delivery_id, input) do
    Repo.transaction(fn ->
      trigger = Repo.one(from(t in Trigger, where: t.id == ^id and t.kind == "webhook", lock: "FOR UPDATE"))

      if is_nil(trigger) or not trigger.enabled or
           not Plug.Crypto.secure_compare(trigger.token_hash, :crypto.hash(:sha256, secret)),
         do: Repo.rollback(:unauthorized)

      key = "webhook:#{id}:#{delivery_id}"

      case Repo.get_by(Run, admission_key: key) do
        nil ->
          actor = Users.get_user(trigger.execution_user_id)
          revision = Repo.get!(Revision, trigger.revision_id)

          case admit(actor, revision, input, "webhook", key, interface: "api") do
            {:ok, run} -> run
            {:error, reason} -> Repo.rollback(reason)
          end

        run ->
          run
      end
    end)
  end

  defp schedule_one(id) do
    Repo.transaction(fn ->
      trigger = Repo.one(from(t in Trigger, where: t.id == ^id, lock: "FOR UPDATE"))

      if (trigger && trigger.enabled) and DateTime.compare(trigger.next_run_at, now()) != :gt do
        active =
          Repo.exists?(
            from(r in Run,
              where:
                r.trigger == "schedule" and like(r.admission_key, ^"schedule:#{id}:%") and
                  r.status in ["queued", "running", "waiting_approval"]
            )
          )

        if !active do
          actor = Users.get_user(trigger.execution_user_id)
          revision = Repo.get!(Revision, trigger.revision_id)

          admit(actor, revision, trigger.input, "schedule", "schedule:#{id}:#{DateTime.to_unix(trigger.next_run_at)}",
            interface: "worker"
          )
        end

        next = trigger.cron |> Expression.parse!() |> Expression.next_at()
        trigger |> Ecto.Changeset.change(next_run_at: next) |> Repo.update!()
      end
    end)
  end

  defp trigger_section(%{kind: "schedule"}), do: "schedules"
  defp trigger_section(_), do: "webhooks"
end
