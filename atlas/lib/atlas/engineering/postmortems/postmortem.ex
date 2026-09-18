defmodule Atlas.Engineering.Postmortems.Postmortem do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @visibilities [:public, :private]

  schema "postmortems" do
    field :number, :integer, read_after_writes: true
    field :body, :string
    field :visibility, Ecto.Enum, values: @visibilities, default: :public

    belongs_to :created_by_user, Atlas.Users.User
    field :domain_ids, {:array, :binary_id}, virtual: true

    many_to_many :domains, Atlas.Engineering.Domains.Domain,
      join_through: "domains_postmortems",
      join_keys: [postmortem_id: :id, domain_id: :id],
      on_replace: :delete

    has_many :action_items, Atlas.Engineering.Postmortems.ActionItem

    timestamps(type: :utc_datetime)
  end

  def visibilities, do: @visibilities

  def changeset(postmortem, attrs) do
    postmortem
    |> cast(attrs, [:body, :visibility, :domain_ids])
    |> validate_required([:body, :visibility])
    |> validate_length(:body, min: 10, max: 100_000)
    |> validate_inclusion(:visibility, @visibilities)
    |> foreign_key_constraint(:created_by_user_id)
  end
end
