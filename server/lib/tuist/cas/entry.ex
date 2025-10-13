defmodule Tuist.CAS.Entry do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "cas_entries" do
    field :id, Ecto.UUID
    field :cas_id, :string
    field :key, :string
    field :value, :string
    field :project_id, :integer

    field :inserted_at, :naive_datetime
  end
end