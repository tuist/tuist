defmodule Atlas.Engineering.Specs.Revision do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Engineering.Specs.Spec
  alias Atlas.Engineering.Specs.Status
  alias Atlas.Users.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "spec_revisions" do
    field :revision, :integer
    field :title, :string
    field :body, :string
    field :summary, :string
    field :status, Ecto.Enum, values: Status.values()

    belongs_to :spec, Spec
    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(revision, attrs) do
    revision
    |> cast(attrs, [:revision, :title, :body, :summary, :status, :spec_id, :user_id])
    |> validate_required([:revision, :title, :body, :status, :spec_id])
    |> unique_constraint([:spec_id, :revision])
    |> foreign_key_constraint(:spec_id)
  end
end
