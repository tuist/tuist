defmodule Tuist.Bazel.ProfileSteps do
  @moduledoc "Indexed profile intervals for bounded step queries, published before profile metadata."
  use Ecto.Schema

  import Ecto.Query

  alias Tuist.Bazel.Action
  alias Tuist.Bazel.RemoteExecutionProfile
  alias Tuist.Builds.StepOptions
  alias Tuist.Builds.Steps
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.MCP.Components.Tools.RunnerTools

  @fields [:event_id, :title, :project, :target, :category, :primary_output, :start_ms, :duration_ms] ++
            RemoteExecutionProfile.fields()
  @primary_key false
  schema "bazel_profile_steps" do
    field :project_id, Ch, type: "Int64"
    field :invocation_id, Ch, type: "String"
    field :version, :string
    field :event_id, :string
    field :title, :string
    field :project, :string
    field :target, :string
    field :category, :string
    field :primary_output, :string
    field :start_ms, Ch, type: "Float64"
    field :duration_ms, Ch, type: "Float64"
    field :profile_started_at_ms, Ch, type: "UInt64"
    field :inserted_at, Ch, type: "DateTime"
    field :remote_queue_ms, Ch, type: "Nullable(Float64)"
    field :remote_input_fetch_ms, Ch, type: "Nullable(Float64)"
    field :remote_execution_ms, Ch, type: "Nullable(Float64)"
    field :remote_output_upload_ms, Ch, type: "Nullable(Float64)"
  end

  def insert(project, id, version, timeline) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    timeline.events
    |> Enum.chunk_every(1000)
    |> Enum.each(fn steps ->
      rows =
        Enum.map(steps, fn step ->
          step
          |> then(&Map.new(@fields, fn field -> {field, Map.get(&1, field)} end))
          |> Map.merge(%{
            project_id: project.id,
            invocation_id: id,
            version: version,
            profile_started_at_ms: timeline.profile_started_at_ms || 0,
            inserted_at: now
          })
        end)

      IngestRepo.insert_all(__MODULE__, rows)
    end)
  end

  def available?(invocation, version), do: ClickHouseRepo.exists?(query(invocation, version))

  def events(invocation, version) do
    # The full-build timeline does not render phase measurements. Keep them in
    # bounded step reads instead of widening every downloaded profile interval.
    fields = (@fields -- RemoteExecutionProfile.fields()) ++ [:status, :action_started_at_ms]

    invocation
    |> outcomes(version)
    |> select([s], map(s, ^fields))
    |> order_by([s], asc: s.start_ms, asc: s.event_id)
    |> ClickHouseRepo.all()
  end

  def list(invocation, version, params) do
    with {:ok, opts} <-
           StepOptions.options(
             params,
             ~w(success failure unknown local_hit remote_hit cache_hit up_to_date skipped no_source)
           ) do
      base = outcomes(invocation, version)
      filtered = base |> remote_filter(params) |> Steps.filter(opts)
      count = ClickHouseRepo.aggregate(filtered, :count)

      steps =
        filtered
        |> Steps.order(opts.sort_by, opts[:sort_order])
        |> limit(^opts.page_size)
        |> offset(^((opts.page - 1) * opts.page_size))
        |> ClickHouseRepo.all()
        |> Enum.map(&serialize/1)

      {:ok,
       %{
         steps: steps,
         availability: if(count > 0 or ClickHouseRepo.exists?(base), do: "available", else: "unavailable"),
         coverage: "trace_profile",
         time_origin: "profile_start",
         pagination_metadata: RunnerTools.pagination_metadata(opts.page, opts.page_size, count)
       }}
    end
  end

  def get(invocation, version, id) do
    case ClickHouseRepo.one(from(s in outcomes(invocation, version), where: s.event_id == ^id, limit: 1)) do
      nil -> {:error, :not_found}
      step -> {:ok, Map.merge(serialize(step), Action.log(invocation, step))}
    end
  end

  @doc """
  The primary output of each of `event_ids` in the invocation's published
  profile, for linking actions to their remote execution records. Steps without
  an output are left out.
  """
  def primary_outputs(_invocation, []), do: %{}

  def primary_outputs(invocation, event_ids) do
    case Tuist.Bazel.Profile.steps_version(invocation) do
      version when is_binary(version) and version != "" ->
        from(s in query(invocation, version),
          where: s.event_id in ^event_ids and s.primary_output != "",
          select: {s.event_id, s.primary_output}
        )
        |> ClickHouseRepo.all()
        |> Map.new()

      _ ->
        %{}
    end
  end

  def remote_only?(params), do: Map.get(params, :remote_execution, Map.get(params, "remote_execution")) in [true, "true"]

  defp remote_filter(query, params) do
    if remote_only?(params) do
      from(s in query,
        where:
          not is_nil(s.remote_queue_ms) or not is_nil(s.remote_input_fetch_ms) or
            not is_nil(s.remote_execution_ms) or not is_nil(s.remote_output_upload_ms)
      )
    else
      query
    end
  end

  defp query(invocation, version) do
    from(s in __MODULE__,
      hints: ["FINAL"],
      where: s.project_id == ^invocation.project_id and s.invocation_id == ^invocation.invocation_id,
      where: s.version == ^version
    )
  end

  defp outcomes(invocation, version) do
    # Bound the right side of the join to this invocation and exclude diagnostic bodies.
    actions =
      from(a in Action,
        where: a.project_id == ^invocation.project_id and a.invocation_id == ^invocation.invocation_id,
        select: map(a, [:project_id, :invocation_id, :primary_output, :status, :started_at_ms])
      )

    # Aggregate distinct executions after the join. Multiple matching attempts remain unknown.
    joined =
      from(s in query(invocation, version),
        left_join: a in subquery(actions),
        on:
          a.project_id == s.project_id and a.primary_output == s.primary_output and
            a.invocation_id == s.invocation_id,
        group_by: [
          s.event_id,
          s.title,
          s.project,
          s.target,
          s.category,
          s.primary_output,
          s.start_ms,
          s.duration_ms,
          s.remote_queue_ms,
          s.remote_input_fetch_ms,
          s.remote_execution_ms,
          s.remote_output_upload_ms
        ],
        select: map(s, ^@fields),
        select_merge: %{
          actions:
            fragment(
              "arrayDistinct(groupArrayIf(tuple(?, ?), ? != '' AND (? = 0 OR ? = 0 OR (? >= floor(? + ?) AND ? <= ceil(? + ? + ?)))))",
              a.status,
              a.started_at_ms,
              a.primary_output,
              s.profile_started_at_ms,
              a.started_at_ms,
              a.started_at_ms,
              s.profile_started_at_ms,
              s.start_ms,
              a.started_at_ms,
              s.profile_started_at_ms,
              s.start_ms,
              s.duration_ms
            )
        }
      )

    from(s in subquery(joined),
      select: map(s, ^@fields),
      select_merge: %{
        status: fragment("if(length(?) = 1, tupleElement(arrayElement(?, 1), 1), 'unknown')", s.actions, s.actions),
        action_started_at_ms: fragment("if(length(?) = 1, tupleElement(arrayElement(?, 1), 2), 0)", s.actions, s.actions)
      }
    )
    |> subquery()
    |> then(&from(s in &1))
  end

  defp serialize(step),
    do: step |> Map.put(:id, step.event_id) |> Map.drop([:event_id, :primary_output, :action_started_at_ms])
end
