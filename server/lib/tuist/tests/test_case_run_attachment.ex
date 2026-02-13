defmodule Tuist.Tests.TestCaseRunAttachment do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_run_attachments" do
    field :test_case_run_id, :string
    field :file_name, Ch, type: "String"
    field :content_type, Ch, type: "String"
    field :size, Ch, type: "UInt64"
    field :s3_object_key, Ch, type: "String"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def create_changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:id, :test_case_run_id, :file_name, :content_type, :size, :s3_object_key, :inserted_at])
    |> validate_required([:id, :test_case_run_id, :file_name, :s3_object_key])
  end
end
