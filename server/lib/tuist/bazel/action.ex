defmodule Tuist.Bazel.Action do
  @moduledoc "Action results and separately fetched diagnostic output from Bazel's BEP."
  use Ecto.Schema

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
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

  defguardp valid_start(value) when is_integer(value) and value >= 0

  defguardp valid_identifier(value, max) when is_binary(value) and byte_size(value) in 1..max

  def ingest(project, %{
        "invocation_id" => invocation,
        "primary_output" => output,
        "started_at_ms" => started,
        "success" => success,
        "log" => log,
        "log_truncated" => truncated
      })
      when valid_identifier(invocation, 255) and valid_identifier(output, 1024) and valid_start(started) and
             is_boolean(success) and is_boolean(truncated) and is_binary(log) and byte_size(log) <= 256 * 1024 do
    IngestRepo.insert_all(__MODULE__, [
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
    ])

    :ok
  end

  def ingest(_, _), do: {:error, :invalid_action}

  def enrich(timeline, invocation) do
    actions =
      from(a in __MODULE__,
        where: a.project_id == ^invocation.project_id and a.invocation_id == ^invocation.invocation_id,
        select: map(a, [:primary_output, :started_at_ms, :status])
      )
      |> ClickHouseRepo.all()
      |> Enum.uniq_by(&{&1.primary_output, &1.started_at_ms})
      |> Enum.group_by(& &1.primary_output)

    events =
      Enum.map(timeline.events, fn step ->
        case actions[step[:primary_output]] do
          [action] -> Map.merge(step, %{status: action.status, action_started_at_ms: action.started_at_ms})
          _ -> step
        end
      end)

    %{timeline | events: events, logs_available: map_size(actions) > 0}
  end

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
