defmodule Atlas.Automations.Interface do
  @moduledoc false

  alias Atlas.Automations
  alias Atlas.Automations.Catalog
  alias Atlas.Automations.Contract
  alias Atlas.Automations.DomainRegistry
  alias Atlas.Automations.ExecutionQuery
  alias Atlas.Automations.Interfaces
  alias Atlas.Automations.ListQuery
  alias Atlas.Automations.Native
  alias Atlas.Automations.Resources

  @object %{"type" => "object"}
  @string %{"type" => "string"}

  def schema(:catalog), do: object(%{}, [])

  def schema(:list) do
    object(
      %{
        "kind" => %{"type" => "string", "enum" => Interfaces.kinds()},
        "page" => %{"type" => "integer", "minimum" => 1, "maximum" => 100_000},
        "workflow_id" => @string,
        "run_id" => @string,
        "days" => %{"type" => "integer", "minimum" => 1, "maximum" => 90},
        "end_date" => @string,
        "q" => %{
          "type" => "string",
          "maxLength" => 120,
          "description" => "Search list metadata only, never source, inputs, outputs, approval payloads or credentials."
        },
        "status" => %{
          "type" => "string",
          "enum" => Enum.uniq(ExecutionQuery.statuses() ++ ~w(pending approved published draft enabled paused)),
          "description" =>
            "Kind-specific state: execution/approval status, workflow publication, or enabled/paused triggers."
        },
        "status_op" => %{
          "type" => "string",
          "enum" => ["==", "!="],
          "description" => "Defaults to ==."
        },
        "trigger" => %{
          "type" => "string",
          "enum" => ExecutionQuery.triggers(),
          "description" => "Execution lists only."
        },
        "trigger_op" => %{
          "type" => "string",
          "enum" => ["==", "!="],
          "description" => "Execution lists only; defaults to ==."
        },
        "language" => %{"type" => "string", "enum" => ~w(json javascript)},
        "language_op" => %{"type" => "string", "enum" => ["==", "!="]},
        "behavior_type" => %{"type" => "string", "maxLength" => 120},
        "behavior_type_op" => %{"type" => "string", "enum" => ["==", "!="]},
        "workflow" => %{"type" => "string", "maxLength" => 120},
        "workflow_op" => %{"type" => "string", "enum" => ["==", "=~", "!=~"]},
        "reviewer" => %{"type" => "string", "maxLength" => 120},
        "reviewer_op" => %{"type" => "string", "enum" => ["==", "=~", "!=~"]},
        "sort_by" => %{
          "type" => "string",
          "enum" =>
            Enum.uniq(
              ExecutionQuery.sort_fields() ++
                Enum.flat_map(~w(workflows behaviors approvals schedules webhooks), &ListQuery.sort_fields/1)
            ),
          "description" => "Kind-specific metadata field; defaults to created."
        },
        "sort_order" => %{
          "type" => "string",
          "enum" => ["asc", "desc"],
          "description" => "Defaults to desc."
        }
      },
      ["kind"]
    )
  end

  def schema(operation) when operation in [:get_workflow, :validate, :publish, :get_run],
    do: object(%{"id" => @string}, ["id"])

  def schema(:get_record),
    do: object(%{"kind" => %{"type" => "string", "enum" => Interfaces.kinds()}, "id" => @string}, ["kind", "id"])

  def schema(:update_workflow), do: partial(schema(:save), ~w(id name description language source input_schema))

  def schema(:update_behavior),
    do: partial(schema(:behavior), ~w(id name description type configuration input_schema output_schema))

  def schema(:update_trigger), do: partial(schema(:trigger), ~w(id name kind cron input enabled))
  def schema(:delete_workflow), do: object(%{"id" => @string}, ["id"])
  def schema(:delete_behavior), do: object(%{"id" => @string}, ["id"])

  def schema(operation) when operation in [:delete_trigger, :rotate_trigger],
    do: object(%{"id" => @string, "kind" => %{"type" => "string", "enum" => ~w(schedule webhook)}}, ["id"])

  def schema(:trace) do
    object(%{"id" => @string, "page" => %{"type" => "integer", "minimum" => 1}}, ["id"])
  end

  def schema(:save) do
    object(
      %{
        "id" => @string,
        "name" => @string,
        "description" => @string,
        "language" => %{"type" => "string", "enum" => ["json", "javascript"]},
        "source" => @string,
        "input_schema" => @object,
        "publish" => %{"type" => "boolean"},
        "expected_revision_id" => %{"type" => ["string", "null"]}
      },
      ["name", "source"]
    )
  end

  def schema(:analytics) do
    object(
      %{
        "workflow_id" => @string,
        "days" => %{"type" => "integer", "minimum" => 1, "maximum" => 90},
        "end_date" => @string
      },
      []
    )
  end

  def schema(:run),
    do:
      object(%{"id" => @string, "input" => @object, "revision_id" => @string, "request_id" => @string}, ["id", "input"])

  def schema(:behavior) do
    object(
      %{
        "name" => @string,
        "description" => @string,
        "type" => %{
          "type" => "string",
          "maxLength" => 160,
          "description" =>
            "Registered behavior name, optionally pinned as name@version. Discover contracts with list_automation_types."
        },
        "configuration" => @object,
        "input_schema" => @object,
        "output_schema" => @object
      },
      ["name", "type"]
    )
  end

  def schema(:trigger) do
    object(
      %{
        "workflow_id" => @string,
        "name" => @string,
        "kind" => %{"type" => "string", "enum" => ["schedule", "webhook"]},
        "cron" => @string,
        "input" => @object
      },
      ["workflow_id", "name", "kind"]
    )
  end

  def schema(:control),
    do: object(%{"id" => @string, "action" => %{"type" => "string", "enum" => ["retry", "cancel"]}}, ["id", "action"])

  def schema(:toggle),
    do:
      object(
        %{
          "id" => @string,
          "enabled" => %{"type" => "boolean"},
          "kind" => %{"type" => "string", "enum" => ~w(schedule webhook)}
        },
        ["id", "enabled"]
      )

  def schema(:decide) do
    object(%{"id" => @string, "decision" => %{"type" => "string", "enum" => ["approved", "rejected"]}}, [
      "id",
      "decision"
    ])
  end

  def output_schema do
    %{"type" => "object", "required" => ["data"], "properties" => %{"data" => @object}}
  end

  def execute(operation, actor, args, opts \\ []) do
    with :ok <- Automations.authorize(actor, Interfaces.access(operation)),
         :ok <- Contract.validate(schema(operation), args),
         {:ok, data} <- dispatch(operation, actor, args, opts) do
      {:ok, %{data: serialize(data)}}
    end
  end

  defp dispatch(:catalog, actor, _, _opts) do
    with :ok <- Automations.authorize(actor, :read) do
      {:ok,
       %{
         types: Catalog.types(),
         domain_policies: DomainRegistry.domain_policies(),
         excluded_domain_tools: DomainRegistry.exclusions(),
         primitives: Interfaces.primitives(),
         operations:
           Enum.map(Interfaces.operations(), fn operation ->
             operation
             |> Map.take([:operation, :access, :method, :path, :mcp])
             |> Map.put(:input_schema, schema(operation.operation))
             |> Map.put(:output_schema, output_schema())
           end),
         plan_contract: %{
           steps: "1–32 ordered steps",
           action: %{
             id: "unique lowercase identifier",
             behavior: "built-in type name or saved behavior UUID",
             inputs: "object; references use {$ref: input.field} or {$ref: steps.prior_id.field}"
           },
           approval: %{
             id: "unique identifier",
             type: "approval",
             reviewer_id: "Atlas user UUID",
             inputs: "exact object to approve"
           }
         },
         javascript:
           "Function body receiving input and returning an object. No host APIs. Linux isolated execution only."
       }}
    end
  end

  defp dispatch(:list, _actor, %{"kind" => "types"}, _opts),
    do: {:ok, %{items: Catalog.types(), page: 1, total_pages: 1, total_count: length(Catalog.types())}}

  defp dispatch(:list, actor, args, _opts) do
    result =
      case args["kind"] do
        "workflows" -> Automations.list_workflows(actor, args)
        "behaviors" -> Automations.list_behaviors(actor, args)
        "executions" -> Automations.list_runs(actor, args)
        "approvals" -> Automations.list_approvals(actor, args)
        "schedules" -> Automations.list_triggers(actor, "schedule", args)
        "webhooks" -> Automations.list_triggers(actor, "webhook", args)
        kind when kind in ~w(revisions attempts events triggers) -> Resources.list(actor, kind, args)
        _ -> {:error, :invalid_kind}
      end

    with {:ok, {items, meta}} <- result,
         do:
           {:ok, %{items: items, page: meta.current_page, total_pages: meta.total_pages, total_count: meta.total_count}}
  end

  defp dispatch(:analytics, actor, args, _opts), do: Automations.execution_analytics(actor, args)
  defp dispatch(:get_workflow, actor, args, _opts), do: Automations.get_workflow(actor, args["id"])
  defp dispatch(:get_run, actor, args, _opts), do: Automations.get_run(actor, args["id"])
  defp dispatch(:get_record, actor, args, _opts), do: Resources.get(actor, args["kind"], args["id"])
  defp dispatch(:trace, actor, args, _opts), do: Automations.execution_trace(actor, args["id"], args)
  defp dispatch(:validate, actor, args, _opts), do: Automations.validate_workflow(actor, args["id"])
  defp dispatch(:publish, actor, args, opts), do: Automations.publish_workflow(actor, args["id"], opts)

  defp dispatch(:update_workflow, actor, args, opts), do: Automations.update_workflow(actor, args["id"], args, opts)
  defp dispatch(:delete_workflow, actor, args, opts), do: Resources.delete_workflow(actor, args["id"], opts)
  defp dispatch(:update_behavior, actor, args, opts), do: Resources.update_behavior(actor, args["id"], args, opts)
  defp dispatch(:delete_behavior, actor, args, opts), do: Resources.delete_behavior(actor, args["id"], opts)
  defp dispatch(:update_trigger, actor, args, opts), do: Resources.update_trigger(actor, args["id"], args, opts)
  defp dispatch(:delete_trigger, actor, args, opts), do: Resources.delete_trigger(actor, args["id"], args, opts)
  defp dispatch(:rotate_trigger, actor, args, opts), do: Resources.rotate_trigger(actor, args["id"], args, opts)

  defp dispatch(:run, actor, args, opts) do
    case {args["revision_id"], args["request_id"]} do
      {nil, nil} ->
        Automations.run_workflow(actor, args["id"], args["input"], opts)

      {revision, request} when is_binary(revision) and is_binary(request) ->
        with {:ok, run} <- Native.run(actor, args["id"], revision, request, args["input"], opts),
             do: Automations.get_run(actor, run.id)

      _ ->
        {:error, :revision_and_request_required}
    end
  end

  defp dispatch(:behavior, actor, args, opts), do: Automations.create_behavior(actor, args, opts)
  defp dispatch(:trigger, actor, args, opts), do: Automations.create_trigger(actor, args["workflow_id"], args, opts)
  defp dispatch(:toggle, actor, args, opts), do: Resources.update_trigger(actor, args["id"], args, opts)
  defp dispatch(:control, actor, args, opts), do: Automations.control_run(actor, args["id"], args["action"], opts)
  defp dispatch(:decide, actor, args, opts), do: Automations.decide_approval(actor, args["id"], args["decision"], opts)

  defp dispatch(:save, actor, %{"publish" => true} = args, opts) do
    opts =
      if Map.has_key?(args, "expected_revision_id"),
        do: Keyword.put(opts, :expected_revision_id, args["expected_revision_id"]),
        else: opts

    Automations.save_workflow_version(actor, args["id"], args, opts)
  end

  defp dispatch(:save, actor, %{"id" => id} = args, opts), do: Automations.update_workflow(actor, id, args, opts)
  defp dispatch(:save, actor, args, opts), do: Automations.create_workflow(actor, args, opts)

  defp partial(schema, fields) do
    properties =
      schema["properties"] |> Map.put("id", @string) |> Map.put("enabled", %{"type" => "boolean"}) |> Map.take(fields)

    object(properties, ["id"])
  end

  defp object(properties, required),
    do: %{"type" => "object", "properties" => properties, "required" => required, "additionalProperties" => false}

  defp serialize(%DateTime{} = date), do: DateTime.to_iso8601(date)
  defp serialize(%Ecto.Association.NotLoaded{}), do: nil

  defp serialize(%_{} = record) do
    record
    |> Map.from_struct()
    |> Map.drop([
      :__meta__,
      :token_hash,
      :created_by,
      :published_by,
      :initiated_by,
      :reviewer,
      :decided_by,
      :execution_user,
      :workflow
    ])
    |> serialize()
  end

  defp serialize(value) when is_map(value), do: Map.new(value, fn {key, item} -> {key, serialize(item)} end)
  defp serialize(value) when is_list(value), do: Enum.map(value, &serialize/1)
  defp serialize(value), do: value
end
