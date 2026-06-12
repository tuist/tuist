defmodule TuistRegistry.S3Transfer do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, UUIDv7.Type, autogenerate: true}

  schema "s3_transfers" do
    field :type, Ecto.Enum, values: [:upload, :download]
    field :account_handle, :string
    field :project_handle, :string
    field :artifact_type, Ecto.Enum, values: [registry: "registry"]
    field :key, :string
    field :inserted_at, :utc_datetime
  end
end
