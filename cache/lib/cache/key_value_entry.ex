defmodule Cache.KeyValueEntry do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "key_value_entries" do
    field :key, :string
    field :json_payload, :string

    timestamps()
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:key, :json_payload])
    |> validate_required([
      :key,
      :json_payload
    ])
    |> unique_constraint(:key)
  end
end
