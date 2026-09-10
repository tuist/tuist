defmodule Tuist.Builds.Steps do
  @moduledoc """
  Bounded, deduplicated access to recorded build steps for API and MCP clients.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Tuist.Builds.Step
  alias Tuist.ClickHouseRepo

  @fields [:event_id, :title, :project, :target, :category, :start_ms, :duration_ms, :status]
  @types %{
    page: :integer,
    page_size: :integer,
    search: :string,
    project: :string,
    target: :string,
    category: :string,
    status: :string,
    start_ms: :float,
    end_ms: :float,
    sort_by: :string
  }

  def list(build, params \\ %{}) do
    with {:ok, opts} <- options(params) do
      base = query(build.id)
      filtered = filter(base, opts)
      count = ClickHouseRepo.aggregate(filtered, :count)
      recorded? = count > 0 or ClickHouseRepo.exists?(base)
      pages = ceil(count / opts.page_size)

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
         pagination_metadata: %{
           current_page: opts.page,
           page_size: opts.page_size,
           total_count: count,
           total_pages: pages,
           has_next_page: opts.page < pages,
           has_previous_page: opts.page > 1
         }
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

  defp options(params) do
    changeset =
      {%{page: 1, page_size: 20, sort_by: "duration_ms"}, @types}
      |> Changeset.cast(params, Map.keys(@types))
      |> Changeset.validate_required([:page, :page_size, :sort_by])
      |> Changeset.validate_number(:page, greater_than: 0, less_than_or_equal_to: 100_000)
      |> Changeset.validate_number(:page_size, greater_than: 0, less_than_or_equal_to: 100)
      |> Changeset.validate_number(:start_ms, greater_than_or_equal_to: 0)
      |> Changeset.validate_number(:end_ms, greater_than_or_equal_to: 0)
      |> Changeset.validate_length(:search, max: 512)
      |> Changeset.validate_length(:project, max: 512)
      |> Changeset.validate_length(:target, max: 512)
      |> Changeset.validate_length(:category, max: 128)
      |> Changeset.validate_inclusion(:status, ["success", "failure"])
      |> Changeset.validate_inclusion(:sort_by, ["duration_ms", "start_ms"])

    case Changeset.apply_action(changeset, :validate) do
      {:ok, opts} ->
        if opts[:start_ms] && opts[:end_ms] && opts.end_ms <= opts.start_ms,
          do: {:error, :invalid_range},
          else: {:ok, opts}

      {:error, _changeset} ->
        {:error, :invalid_filters}
    end
  end

  defp filter(query, opts) do
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

  defp order(query, "start_ms"), do: from(e in query, order_by: [asc: e.start_ms, asc: e.event_id])
  defp order(query, "duration_ms"), do: from(e in query, order_by: [desc: e.duration_ms, asc: e.event_id])

  defp serialize(step), do: step |> Map.put(:id, to_string(step.event_id)) |> Map.delete(:event_id)
  defp availability(_build, true), do: "available"
  defp availability(%{status: "processing"}, _), do: "processing"
  defp availability(_build, _), do: "unavailable"
end
