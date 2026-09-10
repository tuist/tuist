defmodule Tuist.Bazel.Action do
  @moduledoc "Action results and separately fetched diagnostic output from Bazel's BEP."
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests.Sanitizer

  @primary_key false
  schema "bazel_actions" do
    field :project_id, Ch, type: "Int64"
    field :invocation_id, Ch, type: "String"
    field :primary_output, Ch, type: "String"
    field :started_at_ms, Ch, type: "UInt64"
    field :status, Ch, type: "String"
    field :log, Ch, type: "String"
    field :log_truncated, :boolean
    field :inserted_at, Ch, type: "DateTime"
  end

  defguardp valid_start(value) when is_integer(value) and value >= 0 and value <= 18_446_744_073_709_551_615

  defguardp valid_identifier(value, max) when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= max

  def ingest(project, %{"actions" => actions}) when is_list(actions) and length(actions) in 1..32 do
    rows = Enum.map(actions, &row(project, &1))

    if Enum.all?(rows, &is_map/1) do
      __MODULE__.Buffer.insert_all(rows)
      :ok
    else
      {:error, :invalid_action}
    end
  end

  def ingest(project, action) do
    case row(project, action) do
      %{} = row ->
        __MODULE__.Buffer.insert_all([row])
        :ok

      error ->
        error
    end
  end

  defp row(project, %{
         "invocation_id" => invocation,
         "primary_output" => output,
         "started_at_ms" => started,
         "success" => success,
         "log" => log,
         "log_truncated" => truncated
       })
       when valid_identifier(invocation, 255) and valid_identifier(output, 1024) and valid_start(started) and
              is_boolean(success) and is_boolean(truncated) and is_binary(log) and byte_size(log) <= 256 * 1024 do
    %{
      project_id: project.id,
      invocation_id: invocation,
      primary_output: output,
      started_at_ms: started,
      status: if(success, do: "success", else: "failure"),
      log: Sanitizer.sanitize(log),
      log_truncated: truncated,
      inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    }
  end

  defp row(_, _), do: {:error, :invalid_action}

  def enrich(timeline, invocation) do
    outputs = timeline.events |> Enum.map(& &1[:primary_output]) |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()

    actions =
      from(a in __MODULE__,
        where:
          a.project_id == ^invocation.project_id and a.invocation_id == ^invocation.invocation_id and
            a.primary_output in ^outputs,
        select: map(a, [:primary_output, :started_at_ms, :status])
      )
      |> ClickHouseRepo.all()
      |> Enum.uniq_by(&{&1.primary_output, &1.started_at_ms})
      |> Enum.group_by(& &1.primary_output)

    events =
      Enum.map(timeline.events, fn step ->
        case matching_actions(actions[step[:primary_output]] || [], step, timeline[:profile_started_at_ms]) do
          [action] -> Map.merge(step, %{status: action.status, action_started_at_ms: action.started_at_ms})
          _ -> step
        end
      end)

    %{timeline | events: events, logs_available: map_size(actions) > 0}
  end

  defp matching_actions(actions, step, origin) when is_number(origin) do
    # BEP uses integer epoch milliseconds; profile times retain microseconds.
    first = origin + step.start_ms
    last = first + step.duration_ms

    Enum.filter(
      actions,
      &(&1.started_at_ms == 0 or (&1.started_at_ms >= floor(first) and &1.started_at_ms <= ceil(last)))
    )
  end

  defp matching_actions(actions, _step, _origin), do: actions

  def log(invocation, %{primary_output: output, action_started_at_ms: started}) do
    ClickHouseRepo.one(
      from(a in __MODULE__,
        where:
          a.project_id == ^invocation.project_id and a.invocation_id == ^invocation.invocation_id and
            a.primary_output == ^output and a.started_at_ms == ^started,
        order_by: [desc: a.inserted_at],
        limit: 1,
        select: map(a, [:log, :log_truncated])
      )
    ) || %{log: nil, log_truncated: false}
  end

  def log(_, _), do: %{log: nil, log_truncated: false}
end
