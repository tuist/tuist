defmodule Atlas.GTM.AudienceMembership do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.GTM.Audience
  alias Atlas.GTM.Subscriber

  @statuses ~w(pending subscribed unsubscribed)

  schema "gtm_audience_memberships" do
    field :status, :string, default: "subscribed"
    field :unsubscribed_at, :utc_datetime

    belongs_to :audience, Audience
    belongs_to :subscriber, Subscriber

    timestamps()
  end

  def statuses, do: @statuses

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:status, :unsubscribed_at])
    |> validate_required([:audience_id, :subscriber_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:audience_id, :subscriber_id])
    |> foreign_key_constraint(:audience_id)
    |> foreign_key_constraint(:subscriber_id)
  end
end
