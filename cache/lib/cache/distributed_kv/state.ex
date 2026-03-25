defmodule Cache.DistributedKV.State do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:name, :string, autogenerate: false}
  schema "replication_state" do
    field :watermark_updated_at, :utc_datetime_usec
    field :watermark_key, :string
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [:name, :watermark_updated_at, :watermark_key])
    |> validate_required([:name])
  end
end
