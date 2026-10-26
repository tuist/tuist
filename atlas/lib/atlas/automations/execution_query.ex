defmodule Atlas.Automations.ExecutionQuery do
  @moduledoc "Payload-free execution search, filters and stable ordering before pagination."
  import Ecto.Query

  alias Atlas.Automations.Workflow

  @statuses ~w(queued running waiting_approval succeeded failed rejected cancelled)
  @triggers ~w(manual schedule webhook)
  @fields %{"created" => :inserted_at, "status" => :status, "trigger" => :trigger}

  def statuses, do: @statuses
  def triggers, do: @triggers
  def sort_fields, do: ~w(created workflow status trigger)

  def apply(query, params) do
    query = from [run, revision] in query, join: workflow in Workflow, on: workflow.id == revision.workflow_id
    query = search(query, params["q"])
    query = filter(query, params, "status", :status, @statuses)
    query = filter(query, params, "trigger", :trigger, @triggers)
    direction = if params["sort_order"] == "asc", do: :asc, else: :desc

    case params["sort_by"] do
      "workflow" ->
        order_by(query, [run, _revision, workflow], [
          {^direction, fragment("lower(?)", workflow.name)},
          {^direction, run.id}
        ])

      field ->
        field = Map.get(@fields, field, :inserted_at)
        order_by(query, [run], [{^direction, field(run, ^field)}, {^direction, run.id}])
    end
  end

  defp search(query, value) when is_binary(value) and value != "" do
    value =
      value
      |> String.trim()
      |> String.slice(0, 120)
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    pattern = "%#{value}%"

    where(
      query,
      [run, _revision, workflow],
      ilike(workflow.name, ^pattern) or ilike(fragment("?::text", run.id), ^pattern)
    )
  end

  defp search(query, _), do: query

  defp filter(query, params, key, field, values) do
    value = params[key]

    case {value in values, params["#{key}_op"]} do
      {true, "!="} -> where(query, [run], field(run, ^field) != ^value)
      {true, op} when op in [nil, "=="] -> where(query, [run], field(run, ^field) == ^value)
      _ -> query
    end
  end
end
