defmodule Cache.DistributedKV.State do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:name, :string, autogenerate: false}
  schema "distributed_kv_state" do
    field :updated_at_value, :utc_datetime_usec
    field :key_value, :string
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [:name, :updated_at_value, :key_value])
    |> validate_required([:name])
  end
end
