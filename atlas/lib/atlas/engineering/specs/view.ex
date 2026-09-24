defmodule Atlas.Engineering.Specs.View do
  @moduledoc false

  use Ecto.Schema

  alias Atlas.Engineering.Specs.Spec
  alias Atlas.Users.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "spec_views" do
    field :last_viewed_at, :utc_datetime_usec

    belongs_to :spec, Spec
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end
end
