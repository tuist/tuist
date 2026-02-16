defmodule Tuist.Tests.CrashReport do
  @moduledoc """
  A crash report represents a crash log (.ips file) extracted from an xcresult bundle.
  This is a ClickHouse entity that stores crash report data.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_run_crash_reports" do
    field :exception_type, Ch, type: "LowCardinality(String)"
    field :signal, Ch, type: "LowCardinality(String)"
    field :exception_subtype, Ch, type: "LowCardinality(String)"
    field :triggered_thread_frames, Ch, type: "String"
    field :test_case_run_id, Ecto.UUID
    field :test_case_run_attachment_id, Ecto.UUID
    field :inserted_at, Ch, type: "DateTime64(6)"

    belongs_to :test_case_run, Tuist.Tests.TestCaseRun,
      foreign_key: :test_case_run_id,
      define_field: false

    belongs_to :test_case_run_attachment, Tuist.Tests.TestCaseRunAttachment,
      foreign_key: :test_case_run_attachment_id,
      define_field: false
  end

  def create_changeset(crash_report, attrs) do
    crash_report
    |> cast(attrs, [
      :id,
      :exception_type,
      :signal,
      :exception_subtype,
      :triggered_thread_frames,
      :test_case_run_id,
      :test_case_run_attachment_id,
      :inserted_at
    ])
    |> validate_required([:id, :test_case_run_id, :test_case_run_attachment_id])
  end
end
