defmodule Tuist.Tests.StackTrace do
  @moduledoc """
  A stack trace represents a crash log (.ips file) extracted from an xcresult bundle.
  This is a ClickHouse entity that stores crash stack trace data.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_run_stack_traces" do
    field :exception_type, Ch, type: "String"
    field :signal, Ch, type: "String"
    field :exception_subtype, Ch, type: "String"
    field :triggered_thread_frames, Ch, type: "String"
    field :test_case_run_id, Ecto.UUID
    field :test_case_run_attachment_id, Ch, type: "Nullable(UUID)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def create_changeset(stack_trace, attrs) do
    stack_trace
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
    |> validate_required([:id, :test_case_run_id])
  end
end
