defmodule Cache.KeyValueEntry do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "key_value_entries" do
    field :key, :string
    field :json_payload, :string
    field :source_node, :string
    field :last_accessed_at, :utc_datetime_usec
    field :source_updated_at, :utc_datetime_usec
    field :replication_enqueued_at, :utc_datetime_usec

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:key, :json_payload, :source_node, :last_accessed_at, :source_updated_at, :replication_enqueued_at])
    |> validate_required([
      :key,
      :json_payload,
      :last_accessed_at
    ])
    |> unique_constraint(:key)
  end

  def scope_from_key(key) when is_binary(key) do
    case String.split(key, ":", parts: 4) do
      ["keyvalue", account_handle, project_handle, cas_id] ->
        {:ok,
         %{
           account_handle: account_handle,
           project_handle: project_handle,
           cas_id: cas_id
         }}

      _ ->
        :error
    end
  end
end
