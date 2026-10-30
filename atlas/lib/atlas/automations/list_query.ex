defmodule Atlas.Automations.ListQuery do
  @moduledoc "Metadata-only search, allowlisted filters and stable SQL ordering for Automation inventories."
  import Ecto.Query

  alias Atlas.Automations.Approval
  alias Atlas.Automations.Behavior
  alias Atlas.Automations.Revision
  alias Atlas.Automations.Run
  alias Atlas.Automations.Trigger
  alias Atlas.Automations.Workflow
  alias Atlas.Users.User

  def apply(kind, params) do
    kind |> base() |> search(kind, params["q"]) |> filters(kind, params) |> sort(kind, params)
  end

  def sort_fields("workflows"), do: ~w(name status language created)
  def sort_fields("behaviors"), do: ~w(name type created)
  def sort_fields("approvals"), do: ~w(name workflow status reviewer created)
  def sort_fields("schedules"), do: ~w(name workflow status cron next_run created)
  def sort_fields(_), do: ~w(name workflow status endpoint created)

  defp base("workflows") do
    from item in Workflow,
      as: :item,
      left_join: revision in Revision,
      as: :revision,
      on: revision.id == item.published_revision_id
  end

  defp base("behaviors"), do: from(item in Behavior, as: :item)

  defp base("approvals") do
    from item in Approval,
      as: :item,
      join: run in Run,
      on: run.id == item.run_id,
      join: revision in Revision,
      on: revision.id == run.revision_id,
      join: workflow in Workflow,
      as: :workflow,
      on: workflow.id == revision.workflow_id,
      join: reviewer in User,
      as: :reviewer,
      on: reviewer.id == item.reviewer_id
  end

  defp base(kind) do
    query =
      from item in Trigger,
        as: :item,
        join: revision in Revision,
        on: revision.id == item.revision_id,
        join: workflow in Workflow,
        as: :workflow,
        on: workflow.id == revision.workflow_id

    case kind do
      "schedules" -> where(query, [item: item], item.kind == "schedule")
      "webhooks" -> where(query, [item: item], item.kind == "webhook")
      "triggers" -> query
    end
  end

  defp search(query, kind, value) when is_binary(value) and value != "" do
    expression = search_expression(kind, pattern(value))
    where(query, ^expression)
  end

  defp search(query, _, _), do: query

  defp search_expression("workflows", pattern),
    do: dynamic([item: item], ilike(item.name, ^pattern) or ilike(item.description, ^pattern))

  defp search_expression("behaviors", pattern),
    do:
      dynamic(
        [item: item],
        ilike(item.name, ^pattern) or ilike(item.type, ^pattern) or ilike(item.description, ^pattern)
      )

  defp search_expression("approvals", pattern),
    do:
      dynamic(
        [item: item, workflow: workflow, reviewer: reviewer],
        ilike(item.step_id, ^pattern) or ilike(workflow.name, ^pattern) or
          ilike(coalesce(reviewer.name, reviewer.email), ^pattern)
      )

  defp search_expression(_, pattern),
    do:
      dynamic(
        [item: item, workflow: workflow],
        ilike(item.name, ^pattern) or ilike(workflow.name, ^pattern) or ilike(item.cron, ^pattern) or
          ilike(fragment("'/api/automation/hooks/' || ?::text", item.id), ^pattern)
      )

  defp filters(query, "workflows", params) do
    query
    |> option(
      params,
      "status",
      %{"published" => true, "draft" => false},
      dynamic([item: item], not is_nil(item.published_revision_id))
    )
    |> option(
      params,
      "language",
      %{"json" => "json", "javascript" => "javascript"},
      dynamic([item: item, revision: revision], coalesce(revision.language, item.language))
    )
  end

  defp filters(query, "behaviors", params), do: text(query, params, "behavior_type", dynamic([item: item], item.type))

  defp filters(query, "approvals", params) do
    query
    |> option(
      params,
      "status",
      Map.new(~w(pending approved rejected cancelled), &{&1, &1}),
      dynamic([item: item], item.status)
    )
    |> text(params, "workflow", dynamic([workflow: workflow], workflow.name))
    |> text(params, "reviewer", dynamic([reviewer: reviewer], coalesce(reviewer.name, reviewer.email)))
  end

  defp filters(query, _, params) do
    query
    |> option(params, "status", %{"enabled" => true, "paused" => false}, dynamic([item: item], item.enabled))
    |> text(params, "workflow", dynamic([workflow: workflow], workflow.name))
  end

  defp option(query, params, key, choices, expression) do
    case {Map.fetch(choices, params[key]), params["#{key}_op"]} do
      {{:ok, value}, "!="} -> where(query, ^dynamic(^expression != ^value))
      {{:ok, value}, op} when op in [nil, "=="] -> where(query, ^dynamic(^expression == ^value))
      _ -> query
    end
  end

  defp text(query, params, key, expression) do
    value = params[key]

    if is_binary(value) and value != "" do
      value = String.slice(value, 0, 120)

      case params["#{key}_op"] do
        "!=" -> where(query, ^dynamic(^expression != ^value))
        "!=~" -> where(query, ^dynamic(not ilike(^expression, ^pattern(value))))
        "=~" -> where(query, ^dynamic(ilike(^expression, ^pattern(value))))
        op when op in [nil, "=="] -> where(query, ^dynamic(^expression == ^value))
        _ -> query
      end
    else
      query
    end
  end

  defp sort(query, kind, params) do
    field = if params["sort_by"] in sort_fields(kind), do: params["sort_by"], else: "created"
    direction = if params["sort_order"] == "asc", do: :asc_nulls_last, else: :desc_nulls_last
    tie_direction = if params["sort_order"] == "asc", do: :asc, else: :desc
    expression = sort_expression(kind, field)
    order_by(query, ^[{direction, expression}, {tie_direction, dynamic([item: item], item.id)}])
  end

  defp sort_expression(_, "created"), do: dynamic([item: item], item.inserted_at)
  defp sort_expression("approvals", "name"), do: dynamic([item: item], fragment("lower(?)", item.step_id))
  defp sort_expression(_, "name"), do: dynamic([item: item], fragment("lower(?)", item.name))
  defp sort_expression(_, "workflow"), do: dynamic([workflow: workflow], fragment("lower(?)", workflow.name))
  defp sort_expression("workflows", "status"), do: dynamic([item: item], not is_nil(item.published_revision_id))
  defp sort_expression("approvals", "status"), do: dynamic([item: item], item.status)
  defp sort_expression(_, "status"), do: dynamic([item: item], item.enabled)

  defp sort_expression(_, "language"),
    do: dynamic([item: item, revision: revision], coalesce(revision.language, item.language))

  defp sort_expression(_, "type"), do: dynamic([item: item], item.type)

  defp sort_expression(_, "reviewer"),
    do: dynamic([reviewer: reviewer], fragment("lower(?)", coalesce(reviewer.name, reviewer.email)))

  defp sort_expression(_, "cron"), do: dynamic([item: item], item.cron)
  defp sort_expression(_, "next_run"), do: dynamic([item: item], item.next_run_at)
  defp sort_expression(_, "endpoint"), do: dynamic([item: item], item.id)

  defp pattern(value) do
    value =
      value
      |> String.trim()
      |> String.slice(0, 120)
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "%#{value}%"
  end
end
