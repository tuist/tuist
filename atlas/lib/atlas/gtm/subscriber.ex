defmodule Atlas.GTM.Subscriber do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.GTM.AudienceMembership
  alias Atlas.GTM.Delivery

  @statuses ~w(pending subscribed unsubscribed)

  @derive {
    Flop.Schema,
    filterable: [:status, :source, :user_group],
    sortable: [:email, :first_name, :last_name, :inserted_at],
    default_limit: 25,
    max_limit: 100
  }

  schema "gtm_subscribers" do
    field :email, :string
    field :first_name, :string
    field :last_name, :string
    field :user_group, :string
    field :source, :string, default: "atlas"
    field :status, :string, default: "subscribed"
    field :metadata, :map, default: %{}
    field :confirmed_at, :utc_datetime
    field :unsubscribed_at, :utc_datetime
    field :welcomed_at, :utc_datetime

    has_many :audience_memberships, AudienceMembership
    has_many :deliveries, Delivery

    timestamps()
  end

  def statuses, do: @statuses

  def changeset(subscriber, attrs) do
    subscriber
    |> cast(attrs, [
      :email,
      :first_name,
      :last_name,
      :user_group,
      :source,
      :status,
      :metadata,
      :confirmed_at,
      :unsubscribed_at,
      :welcomed_at
    ])
    |> normalize_email()
    |> normalize_optional_fields()
    |> validate_required([:email, :source, :status])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:email, name: :gtm_subscribers_lower_email_index)
  end

  def display_name(%__MODULE__{} = subscriber) do
    [subscriber.first_name, subscriber.last_name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> case do
      "" -> subscriber.email
      name -> name
    end
  end

  defp normalize_email(changeset) do
    update_change(changeset, :email, fn
      nil -> nil
      email -> email |> String.trim() |> String.downcase()
    end)
  end

  defp normalize_optional_fields(changeset) do
    Enum.reduce([:first_name, :last_name, :user_group, :source], changeset, fn field, changeset ->
      update_change(changeset, field, &normalize_optional_string/1)
    end)
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
