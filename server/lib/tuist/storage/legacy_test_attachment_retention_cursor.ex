defmodule Tuist.Storage.LegacyTestAttachmentRetentionCursor do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @artifact_types [:legacy_test_attachment]

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "legacy_test_attachment_retention_cursors" do
    field :artifact_type, Ecto.Enum, values: @artifact_types
    field :completed_before, :utc_datetime_usec
    field :sweep_before, :utc_datetime_usec
    field :after_test_case_run_id, Ecto.UUID
    field :after_id, Ecto.UUID

    timestamps(type: :utc_datetime)
  end

  def changeset(cursor, attrs) do
    cursor
    |> cast(attrs, [:artifact_type, :completed_before, :sweep_before, :after_test_case_run_id, :after_id])
    |> validate_required([:artifact_type, :sweep_before])
    |> unique_constraint(:artifact_type)
  end
end
