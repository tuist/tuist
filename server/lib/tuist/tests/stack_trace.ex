defmodule Tuist.Tests.StackTrace do
  @moduledoc """
  A stack trace represents a crash log (.ips file) extracted from an xcresult bundle.
  This is a ClickHouse entity that stores crash stack trace data.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "stack_traces" do
    field :file_name, Ch, type: "String"
    field :app_name, Ch, type: "String"
    field :os_version, Ch, type: "String"
    field :exception_type, Ch, type: "String"
    field :signal, Ch, type: "String"
    field :exception_subtype, Ch, type: "String"
    field :raw_content, Ch, type: "String"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def create_changeset(stack_trace, attrs) do
    stack_trace
    |> cast(attrs, [
      :id,
      :file_name,
      :app_name,
      :os_version,
      :exception_type,
      :signal,
      :exception_subtype,
      :raw_content,
      :inserted_at
    ])
    |> validate_required([:id, :file_name, :raw_content])
  end
end
