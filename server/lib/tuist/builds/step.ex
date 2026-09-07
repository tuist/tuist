defmodule Tuist.Builds.Step do
  @moduledoc """
  Recorded leaf operations from a build activity log, shared by build analytics views.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "build_steps" do
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
