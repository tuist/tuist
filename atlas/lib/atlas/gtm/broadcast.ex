defmodule Atlas.GTM.Broadcast do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.GTM.Audience
  alias Atlas.GTM.Delivery
  alias Atlas.Users.User

  @statuses ~w(pending sending sent failed)

  schema "gtm_broadcasts" do
    field :subject, :string
    field :body_markdown, :string
    field :from_name, :string
    field :from_email, :string
    field :reply_to_email, :string
    field :status, :string, default: "pending"
    field :source_id, :string
    field :recipients_count, :integer, default: 0
    field :delivered_count, :integer, default: 0
    field :failed_count, :integer, default: 0
    field :skipped_count, :integer, default: 0
    field :sent_at, :utc_datetime

    belongs_to :audience, Audience
    belongs_to :sender, User
    has_many :deliveries, Delivery

    timestamps()
  end

  def statuses, do: @statuses

  def changeset(broadcast, attrs) do
    broadcast
    |> cast(attrs, [:subject, :body_markdown, :from_name, :from_email, :reply_to_email])
    |> normalize_string_fields()
    |> validate_required([:audience_id, :subject, :body_markdown, :from_name, :from_email, :status])
    |> validate_format(:from_email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> validate_format(:reply_to_email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:audience_id)
    |> foreign_key_constraint(:sender_id)
  end

  defp normalize_string_fields(changeset) do
    Enum.reduce([:subject, :body_markdown, :from_name, :from_email, :reply_to_email], changeset, fn field, changeset ->
      update_change(changeset, field, &normalize_string/1)
    end)
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
