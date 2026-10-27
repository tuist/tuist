defmodule Slack.Invitations.Invitation do
  @moduledoc """
  Ecto schema for a Slack workspace invitation request.

  An invitation flows through three states:

    * `:unconfirmed` — just submitted, we've emailed a confirmation link
    * `:pending` — the visitor has clicked the confirmation link
    * `:accepted` — an admin has manually accepted the request
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(unconfirmed pending accepted)a
  @min_reason_length 10
  @max_reason_length 2_000

  schema "invitations" do
    field :email, :string
    field :reason, :string
    field :code_of_conduct_accepted, :boolean, default: false
    field :status, Ecto.Enum, values: @statuses, default: :unconfirmed
    field :confirmation_token, :string
    field :confirmed_at, :utc_datetime
    field :accepted_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def request_changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :reason, :code_of_conduct_accepted])
    |> update_change(:email, &normalize_email/1)
    |> update_change(:reason, &normalize_reason/1)
    |> validate_required([:email, :reason])
    |> validate_length(:email, max: 254)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email address")
    |> validate_length(:reason, min: @min_reason_length, max: @max_reason_length)
    |> validate_acceptance(:code_of_conduct_accepted, message: "must be accepted to continue")
    |> put_confirmation_token()
    |> unique_constraint(:email)
    |> unique_constraint(:confirmation_token)
  end

  def confirm_changeset(invitation, now) do
    change(invitation, status: :pending, confirmed_at: now)
  end

  def accept_changeset(invitation, now) do
    change(invitation, status: :accepted, accepted_at: now)
  end

  defp normalize_email(nil), do: nil
  defp normalize_email(email) when is_binary(email), do: email |> String.trim() |> String.downcase()

  defp normalize_reason(nil), do: nil
  defp normalize_reason(reason) when is_binary(reason), do: String.trim(reason)

  defp put_confirmation_token(changeset) do
    if get_field(changeset, :confirmation_token) do
      changeset
    else
      put_change(changeset, :confirmation_token, generate_token())
    end
  end

  defp generate_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
