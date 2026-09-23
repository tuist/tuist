defmodule Atlas.Engineering.Postmortems.Postmortem do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Engineering.Domains.Domain
  alias Atlas.Engineering.Postmortems.ActionItem
  alias Atlas.Users.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "postmortems" do
    field :number, :integer, read_after_writes: true
    field :body, :string
    field :share_token, Ecto.UUID

    belongs_to :created_by_user, User
    field :domain_ids, {:array, :binary_id}, virtual: true

    many_to_many :domains, Domain,
      join_through: "domains_postmortems",
      join_keys: [postmortem_id: :id, domain_id: :id],
      on_replace: :delete

    has_many :action_items, ActionItem

    timestamps(type: :utc_datetime)
  end

  def changeset(postmortem, attrs) do
    postmortem
    |> cast(attrs, [:body, :domain_ids])
    |> validate_required([:body])
    |> validate_length(:body, min: 10, max: 100_000)
    |> foreign_key_constraint(:created_by_user_id)
  end
end
