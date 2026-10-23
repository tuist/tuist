defmodule Atlas.Automations.Native do
  @moduledoc "Bounded native-client projections and revision-bound, idempotent admissions."
  import Ecto.Query

  alias Atlas.Automations
  alias Atlas.Automations.Approval
  alias Atlas.Automations.Attempt
  alias Atlas.Automations.Contract
  alias Atlas.Automations.DomainAccess
  alias Atlas.Automations.Revision
  alias Atlas.Automations.Run
  alias Atlas.Automations.Workflow
  alias Atlas.Repo

  def workflows(actor, params) do
    with :ok <- Automations.authorize(actor, :read) do
      query =
        from w in DomainAccess.scope(Workflow, actor),
          where: not is_nil(w.published_revision_id),
          order_by: [asc: w.name, asc: w.id],
          select: [:id, :name, :description, :published_revision_id],
          preload: [published_revision: ^from(v in Revision, select: [:id, :number, :input_schema])]

      {items, meta} = paginate(query, params)
      {:ok, %{items: Enum.map(items, &workflow/1), page: page(meta)}}
    end
  end

  def workflow(actor, id) do
    with :ok <- identifier(id), {:ok, w} <- Automations.get_workflow(actor, id) do
      if w.published_revision,
        do:
          {:ok,
           Map.put(
             workflow(w),
             :can_run,
             Automations.authorize(actor, :write) == :ok and
               DomainAccess.authorize_execution(actor, w.published_revision.plan) == :ok
           )},
        else: {:error, :not_published}
    end
  end

  defp workflow(w) do
    r = w.published_revision

    %{
      id: w.id,
      name: w.name,
      description: w.description,
      revision_id: r.id,
      version: r.number,
      input_schema: r.input_schema
    }
  end

  def executions(actor, params) do
    with :ok <- Automations.authorize(actor, :read) do
      query =
        from r in DomainAccess.scope(Run, actor),
          where: r.initiated_by_id == ^actor.id,
          order_by: [desc: r.inserted_at, desc: r.id],
          select: r.id

      {ids, meta} = paginate(query, params)

      {:ok,
       %{
         items:
           Enum.flat_map(ids, fn id ->
             case execution(actor, id) do
               {:ok, item} -> [item]
               _ -> []
             end
           end),
         page: page(meta)
       }}
    end
  end

  def execution(actor, id) do
    with :ok <- Automations.authorize(actor, :read), :ok <- identifier(id) do
      query =
        from r in DomainAccess.scope(Run, actor),
          join: v in Revision,
          on: v.id == r.revision_id,
          join: w in Workflow,
          on: w.id == v.workflow_id,
          where: r.id == ^id,
          select: %{
            id: r.id,
            revision_id: r.revision_id,
            name: w.name,
            version: v.number,
            status: r.status,
            cursor: r.cursor,
            sequence: r.event_sequence,
            initiated_by_id: r.initiated_by_id,
            admitted_at: r.inserted_at,
            precise_admitted_at: r.trace_started_at,
            completed_at: r.completed_at,
            precise_completed_at: r.trace_completed_at,
            step_ids:
              fragment(
                "(SELECT COALESCE(jsonb_agg(step->>'id' ORDER BY ordinal), '[]'::jsonb) FROM jsonb_array_elements(?->'steps') WITH ORDINALITY AS s(step, ordinal))",
                v.plan
              )
          }

      case Repo.one(query) do
        nil ->
          {:error, :not_found}

        run ->
          run =
            run
            |> Map.put(:admitted_at, run.precise_admitted_at || run.admitted_at)
            |> Map.put(:completed_at, run.precise_completed_at || run.completed_at)
            |> Map.drop([:precise_admitted_at, :precise_completed_at])

          attempts =
            Repo.all(
              from a in Attempt,
                where: a.run_id == ^id,
                distinct: a.step_id,
                order_by: [asc: a.step_id, desc: a.inserted_at, desc: a.id],
                select: %{
                  id: a.id,
                  step_id: a.step_id,
                  status: a.status,
                  started_at: a.started_at,
                  completed_at: a.completed_at
                }
            )

          latest = Map.new(attempts, &{&1.step_id, &1})

          steps =
            Enum.map(run.step_ids, fn step ->
              Map.get(latest, step, %{step_id: step, status: "pending", started_at: nil, completed_at: nil})
            end)

          {:ok,
           run
           |> Map.put(:elapsed_ms, elapsed_ms(run))
           |> Map.put(:web_path, "/automation/executions/#{run.id}")
           |> Map.delete(:step_ids)
           |> Map.put(:steps, steps)
           |> Map.put(:can_control, run.initiated_by_id == actor.id and Automations.authorize(actor, :write) == :ok)}
      end
    end
  end

  defp elapsed_ms(run) do
    ending = run.completed_at || if(run.status in ~w(queued running waiting_approval), do: DateTime.utc_now())
    if run.admitted_at && ending, do: max(0, DateTime.diff(ending, run.admitted_at, :millisecond))
  end

  def result(actor, id) do
    with :ok <- Automations.authorize(actor, :read), :ok <- identifier(id) do
      case Repo.one(
             from r in DomainAccess.scope(Run, actor),
               where: r.id == ^id,
               select: %{outputs: r.outputs, status: r.status}
           ) do
        nil ->
          {:error, :not_found}

        value ->
          if Contract.within_budget?(value.outputs, 65_536),
            do:
              {:ok,
               %{outputs_json: display_json(value.outputs), status: value.status, partial: value.status != "succeeded"}},
            else: {:error, :result_too_large}
      end
    end
  end

  def approvals(actor, params) do
    with :ok <- Automations.authorize(actor, :read) do
      query =
        from a in DomainAccess.scope(Approval, actor),
          join: r in Run,
          on: r.id == a.run_id,
          join: v in Revision,
          on: v.id == r.revision_id,
          join: w in Workflow,
          on: w.id == v.workflow_id,
          where: a.reviewer_id == ^actor.id and a.status == "pending",
          order_by: [desc: a.inserted_at, desc: a.id],
          select: %{
            id: a.id,
            run_id: a.run_id,
            step_id: a.step_id,
            status: a.status,
            inserted_at: a.inserted_at,
            name: w.name,
            version: v.number
          }

      {items, meta} = paginate(query, params)
      {:ok, %{items: items, page: page(meta)}}
    end
  end

  def approval(actor, id) do
    with :ok <- Automations.authorize(actor, :read), :ok <- identifier(id) do
      case Repo.one(from a in DomainAccess.scope(Approval, actor), where: a.id == ^id and a.reviewer_id == ^actor.id) do
        nil ->
          {:error, :not_found}

        a ->
          {:ok,
           Map.merge(approval_summary(a), %{
             payload_json: display_json(a.payload),
             payload_digest: digest(a.payload),
             can_decide: Automations.authorize(actor, :write) == :ok
           })}
      end
    end
  end

  def decide(actor, id, decision, digest) when decision in ["approved", "rejected"] and is_binary(digest) do
    with {:ok, a} <- approval(actor, id),
         true <- a.payload_digest == digest,
         {:ok, _} <- Automations.decide_approval(actor, id, decision, interface: "api") do
      execution(actor, a.run_id)
    else
      false -> {:error, :payload_changed}
      error -> error
    end
  end

  def decide(_, _, _, _), do: {:error, :invalid_input}

  def run(actor, workflow_id, revision_id, request_id, input, opts \\ [interface: "api"]) do
    with :ok <- Automations.authorize(actor, :write),
         :ok <- identifier(workflow_id),
         :ok <- identifier(revision_id),
         :ok <- identifier(request_id),
         true <- is_map(input) and Contract.within_budget?(input, 65_536) do
      workflow_id = String.downcase(workflow_id)
      revision_id = String.downcase(revision_id)
      request_id = String.downcase(request_id)
      key = "client:#{actor.id}:#{request_id}"

      result =
        Repo.transaction(fn ->
          Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])

          case Repo.get_by(Run, admission_key: key) do
            %Run{} = existing -> replay!(existing, workflow_id, revision_id, input)
            nil -> admit!(actor, workflow_id, revision_id, key, input, opts)
          end
        end)

      with {:ok, id} <- result, do: execution(actor, id)
    else
      false -> {:error, :invalid_input}
      error -> error
    end
  end

  defp replay!(existing, workflow_id, revision_id, input) do
    revision = Repo.get!(Revision, existing.revision_id)

    if existing.revision_id != revision_id or revision.workflow_id != workflow_id or existing.input !== input,
      do: Repo.rollback(:idempotency_conflict)

    existing.id
  end

  defp admit!(actor, workflow_id, revision_id, key, input, opts) do
    workflow = Repo.one(from w in Workflow, where: w.id == ^workflow_id, lock: "FOR SHARE")
    if is_nil(workflow), do: Repo.rollback(:not_found)
    if workflow.published_revision_id != revision_id, do: Repo.rollback(:revision_changed)
    revision = Repo.get!(Revision, revision_id)

    case Automations.admit(actor, revision, input, "manual", key, opts) do
      {:ok, admitted} -> admitted.id
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def identifier(id) when is_binary(id) and byte_size(id) == 36 do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_input}
    end
  end

  def identifier(_), do: {:error, :invalid_input}

  defp approval_summary(a),
    do: %{id: a.id, run_id: a.run_id, step_id: a.step_id, status: a.status, inserted_at: a.inserted_at}

  defp display_json(payload) do
    pretty = Jason.encode!(payload, pretty: true)
    if byte_size(pretty) <= 131_072, do: pretty, else: JSON.encode!(payload)
  end

  defp digest(payload),
    do: Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary(payload, [:deterministic])), case: :lower)

  defp paginate(query, params) do
    value = params["page"]
    value = if is_binary(value) or is_integer(value), do: to_string(value), else: "1"

    page =
      case Integer.parse(value) do
        {n, ""} when n > 0 and n <= 100_000 -> n
        _ -> 1
      end

    Flop.run(query, %Flop{page: page, page_size: 20}, repo: Repo)
  end

  defp page(meta), do: %{current: meta.current_page, total: meta.total_pages, count: meta.total_count}
end
