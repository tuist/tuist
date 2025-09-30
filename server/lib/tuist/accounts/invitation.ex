defmodule Tuist.Accounts.Invitation do
  @moduledoc ~S"""
  A module that represents an invitation to join an organization.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.User

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
end
