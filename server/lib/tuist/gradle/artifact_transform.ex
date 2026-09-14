defmodule Tuist.Gradle.ArtifactTransform do
  @moduledoc """
  A Gradle artifact transform executed while resolving dependencies.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "gradle_artifact_transforms" do
    field :id, Ch, type: "UUID"
    field :gradle_build_id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :transformer_name, Ch, type: "String"
    field :transform_action_class, Ch, type: "String"
    field :subject_name, Ch, type: "String"
    field :artifact_name, Ch, type: "String"
    field :consumer_project_path, Ch, type: "String"
    field :duration_ms, Ch, type: "UInt64"
    field :started_at, Ch, type: "DateTime64(6)"
    field :inserted_at, Ch, type: "DateTime"
  end
end
