defmodule Cache.DistributedKV.Entry do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:key, :string, autogenerate: false}
  schema "key_value_entries" do
    field :account_handle, :string
    field :project_handle, :string
    field :cas_id, :string
    field :json_payload, :string
    field :source_node, :string
    field :source_updated_at, :utc_datetime_usec
    field :last_accessed_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at, inserted_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :key,
      :account_handle,
      :project_handle,
      :cas_id,
      :json_payload,
      :source_node,
      :source_updated_at,
      :last_accessed_at,
      :deleted_at,
      :updated_at
    ])
    |> validate_required([
      :key,
      :account_handle,
      :project_handle,
      :cas_id,
      :json_payload,
      :source_node,
      :source_updated_at,
      :last_accessed_at,
      :updated_at
    ])
  end
end
