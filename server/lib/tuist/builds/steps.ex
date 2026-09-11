defmodule Tuist.Builds.Steps do
  @moduledoc """
  Bounded, deduplicated access to recorded build steps for API and MCP clients.
  """
  import Ecto.Query

  alias Tuist.Builds.Step
  alias Tuist.Builds.StepOptions
  alias Tuist.ClickHouseRepo
  alias Tuist.MCP.Components.Tools.RunnerTools

  @fields [:event_id, :title, :project, :target, :category, :start_ms, :duration_ms, :status]

  def list(build, params \\ %{}) do
    with {:ok, opts} <- StepOptions.options(params, ["success", "failure"]) do
      base = query(build.id)
      filtered = filter(base, opts)
      count = ClickHouseRepo.aggregate(filtered, :count)
      recorded? = count > 0 or ClickHouseRepo.exists?(base)

      steps =
        filtered
        |> order(opts.sort_by)
        |> limit(^opts.page_size)
        |> offset(^((opts.page - 1) * opts.page_size))
        |> select([e], map(e, ^@fields))
        |> ClickHouseRepo.all()
        |> Enum.map(&serialize/1)

      {:ok,
       %{
         steps: steps,
         availability: availability(build, recorded?),
         pagination_metadata: RunnerTools.pagination_metadata(opts.page, opts.page_size, count)
       }}
    end
  end

  def get(build_id, step_id) do
    with {:ok, id} <- parse_id(step_id) do
      case ClickHouseRepo.one(
             from(e in query(build_id),
               where: e.event_id == ^id,
               select: map(e, ^(@fields ++ [:log, :log_truncated])),
               limit: 1
             )
           ) do
        nil -> {:error, :not_found}
        step -> {:ok, serialize(step)}
      end
    end
  end

  defp query(build_id), do: from(e in Step, hints: ["FINAL"], where: e.build_run_id == ^build_id)

  defp parse_id(value) when is_binary(value) and byte_size(value) <= 20 do
    case Regex.match?(~r/\A[0-9]+\z/, value) && Integer.parse(value) do
      {id, ""} when id >= 0 and id <= 18_446_744_073_709_551_615 -> {:ok, id}
      _ -> {:error, :invalid_step_id}
    end
  end

  defp parse_id(_), do: {:error, :invalid_step_id}

  def filter(query, opts) do
    query =
      Enum.reduce([:project, :target, :category, :status], query, fn key, query ->
        case opts[key] do
          nil -> query
          value -> from(e in query, where: field(e, ^key) == ^value)
        end
      end)

    query =
      case opts[:search] do
        value when is_binary(value) and value != "" ->
          from(e in query,
            where:
              fragment(
                "positionCaseInsensitiveUTF8(concat(?, ' ', ?, ' ', ?), ?) > 0",
                e.title,
                e.project,
                e.target,
                ^value
              )
          )

        _ ->
          query
      end

    query =
      if opts[:start_ms],
        do:
          from(e in query,
            where: e.start_ms >= ^opts.start_ms or fragment("? + ?", e.start_ms, e.duration_ms) > ^opts.start_ms
          ),
        else: query

    if opts[:end_ms], do: from(e in query, where: e.start_ms < ^opts.end_ms), else: query
  end

  def order(query, "start_ms"), do: from(e in query, order_by: [asc: e.start_ms, asc: e.event_id])
  def order(query, "duration_ms"), do: from(e in query, order_by: [desc: e.duration_ms, asc: e.event_id])

  defp serialize(step), do: step |> Map.put(:id, to_string(step.event_id)) |> Map.delete(:event_id)
  defp availability(_build, true), do: "available"
  defp availability(%{status: "processing"}, _), do: "processing"
  defp availability(_build, _), do: "unavailable"
end
