defmodule Tuist.Storage.ArtifactRetentionCursor do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @artifact_types [:preview_app_build, :build_archive, :run_session, :test_attachment, :shard_bundle]

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "artifact_retention_cursors" do
    field :artifact_type, Ecto.Enum, values: @artifact_types
    field :after_inserted_at, :utc_datetime_usec
    field :after_id, :string

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def artifact_types, do: @artifact_types

  def changeset(cursor, attrs) do
    cursor
    |> cast(attrs, [:account_id, :artifact_type, :after_inserted_at, :after_id])
    |> validate_required([:account_id, :artifact_type, :after_inserted_at, :after_id])
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :artifact_type])
  end
end
