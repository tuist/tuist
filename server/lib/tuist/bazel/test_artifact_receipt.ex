defmodule Tuist.Bazel.TestArtifactReceipt do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: false}
  schema "bazel_test_artifact_receipts" do
    field :project_id, :integer
    field :invocation_id, :string
    field :target_label, :string
    field :action_digest, :string
    field :artifact_kind, :string
    field :artifact_digest, :string

    timestamps(type: :utc_datetime)
  end
end
