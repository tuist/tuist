defmodule Tuist.Entire.Delivery do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "ci_deliveries" do
    field :jwt_id, :string
    field :inserted_at, :utc_datetime
  end
end
