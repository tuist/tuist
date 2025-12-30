defmodule Tuist.QA.Log do
  @moduledoc false

  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :qa_run_id,
      :type,
      :timestamp
    ],
    sortable: [:timestamp, :inserted_at]
  }

  @primary_key false
  schema "qa_logs" do
    field :project_id, Ch, type: "Int64"
    field :qa_run_id, Ch, type: "UUID"
    field :data, Ch, type: "String"
    field :type, Ch, type: "Enum8('usage' = 0, 'tool_call' = 1, 'tool_call_result' = 2, 'message' = 3)"
    field :timestamp, Ch, type: "DateTime"
    field :inserted_at, Ch, type: "DateTime"
  end

  def normalize_enums(log) do
    %{
      log
      | type: String.to_atom(log.type)
    }
  end
end
