defmodule Cache.KeyValueEntry do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "key_value_entries" do
    field :key, :string
    field :json_payload, :string
    field :last_accessed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:key, :json_payload, :last_accessed_at])
    |> validate_required([
      :key,
      :json_payload,
      :last_accessed_at
    ])
    |> unique_constraint(:key)
  end
end
