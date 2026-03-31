defmodule Tuist.Tests.TestCaseRunAttachment do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_run_attachments" do
    field :test_case_run_id, Ecto.UUID
    field :test_case_run_argument_id, Ch, type: "Nullable(UUID)"
    field :file_name, Ch, type: "String"
    field :repetition_number, Ch, type: "Nullable(Int32)"
    field :inserted_at, Ch, type: "DateTime64(6)"

    belongs_to :test_case_run, Tuist.Tests.TestCaseRun,
      foreign_key: :test_case_run_id,
      define_field: false
  end

  def create_changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:id, :test_case_run_id, :test_case_run_argument_id, :file_name, :repetition_number, :inserted_at])
    |> validate_required([:id, :test_case_run_id, :file_name])
  end
end
