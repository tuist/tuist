defmodule Cache.S3Transfer do
  @moduledoc """
  Schema for pending S3 transfers.

  This table tracks artifacts that need to be uploaded to or downloaded from S3.
  It replaces per-request Oban job insertion with a simpler queue model that
  avoids SQLite contention under bursty load.
  """

  use Ecto.Schema

  @primary_key {:id, UUIDv7.Type, autogenerate: true}

  schema "s3_transfers" do
    field :type, Ecto.Enum, values: [:upload, :download]
    field :account_handle, :string
    field :project_handle, :string
    field :artifact_type, Ecto.Enum, values: [:cas, :module]
    field :key, :string
    field :inserted_at, :utc_datetime
  end
end
