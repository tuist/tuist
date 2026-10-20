defmodule Tuist.Gradle.ConfigurationOperation do
  @moduledoc """
  A Gradle settings, build, or project configuration operation.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "gradle_configuration_operations" do
    field :id, Ch, type: "UUID"
    field :gradle_build_id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :phase, Ch, type: "LowCardinality(String)"
    field :build_path, Ch, type: "String"
    field :project_path, Ch, type: "String"
    field :duration_ms, Ch, type: "UInt64"
    field :started_at, Ch, type: "DateTime64(6)"
    field :inserted_at, Ch, type: "DateTime"
  end
end
