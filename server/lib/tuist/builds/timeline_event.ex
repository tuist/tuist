defmodule Tuist.Builds.TimelineEvent do
  @moduledoc false
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "build_timeline_events" do
    field :build_run_id, Ecto.UUID
    field :event_id, Ch, type: "UInt64"
    field :title, :string
    field :target, :string
    field :project, :string
    field :category, :string
    field :start_ms, Ch, type: "Float64"
    field :duration_ms, Ch, type: "Float64"
    field :status, :string
    field :log, :string, default: ""
    field :log_truncated, :boolean, default: false
    field :inserted_at, :utc_datetime
  end
end
