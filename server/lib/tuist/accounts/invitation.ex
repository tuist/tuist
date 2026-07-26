defmodule Tuist.Accounts.Invitation do
  @moduledoc ~S"""
  A module that represents an invitation to join an organization.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.User
  alias Tuist.Time

  @validity_days 14
  @validity_seconds @validity_days * 24 * 60 * 60

  schema "invitations" do
    field(:token, :string)
    field(:invitee_email, :string)
    field(:inviter_type, :string, default: "User")
    belongs_to(:inviter, User, foreign_key: :inviter_id)
    belongs_to(:organization, Organization)

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(inserted_at: :created_at)
  end

  def create_changeset(invitation, attrs \\ %{}) do
    invitation
    |> cast(attrs, [:token, :invitee_email, :inviter_id, :organization_id])
    |> update_change(:invitee_email, &String.downcase/1)
    |> validate_required([:token, :invitee_email, :inviter_id, :organization_id])
    |> unique_constraint(:token, name: "index_invitations_on_token")
    |> unique_constraint([:invitee_email, :organization_id])
  end

  def resend_changeset(invitation, attrs \\ %{}) do
    invitation
    |> cast(attrs, [:token])
    |> validate_required([:token])
    |> unique_constraint(:token, name: "index_invitations_on_token")
  end

  def validity_days, do: @validity_days

  def expires_at(%__MODULE__{} = invitation) do
    invitation
    |> sent_at()
    |> NaiveDateTime.add(@validity_seconds, :second)
  end

  def expired?(%__MODULE__{} = invitation, now \\ Time.naive_utc_now()) do
    NaiveDateTime.compare(expires_at(invitation), now) != :gt
  end

  defp sent_at(%__MODULE__{updated_at: %NaiveDateTime{} = updated_at}), do: updated_at
  defp sent_at(%__MODULE__{created_at: %NaiveDateTime{} = created_at}), do: created_at
end
