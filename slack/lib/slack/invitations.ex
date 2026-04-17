defmodule Slack.Invitations do
  @moduledoc """
  The Invitations context: stores requests for Slack workspace
  invitations, sends confirmation emails and exposes functions to
  list, inspect and accept them.

  An invitation moves through three states:

    * `:unconfirmed` — just created, confirmation email sent
    * `:pending` — the visitor clicked the confirmation link
    * `:accepted` — an admin manually accepted the invitation
  """

  import Ecto.Query

  alias Slack.Invitations.Email
  alias Slack.Invitations.Invitation
  alias Slack.Mailer
  alias Slack.Notifier
  alias Slack.Repo

  def request_invitation(attrs, build_confirm_url) when is_function(build_confirm_url, 1) do
    with {:ok, invitation} <-
           %Invitation{}
           |> Invitation.request_changeset(attrs)
           |> Repo.insert() do
      invitation
      |> Email.confirmation(build_confirm_url.(invitation.confirmation_token))
      |> Mailer.deliver()

      {:ok, invitation}
    end
  end

  def change_invitation(%Invitation{} = invitation, attrs \\ %{}) do
    Invitation.request_changeset(invitation, attrs)
  end

  def list_invitations(opts \\ []) do
    statuses = Keyword.get(opts, :statuses, [:pending, :accepted])

    Invitation
    |> where([i], i.status in ^statuses)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  def get_invitation!(id), do: Repo.get!(Invitation, id)

  def get_invitation_by_token(token) when is_binary(token) do
    Repo.get_by(Invitation, confirmation_token: token)
  end

  def confirm_invitation(%Invitation{status: :unconfirmed} = invitation) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    with {:ok, confirmed} <-
           invitation
           |> Invitation.confirm_changeset(now)
           |> Repo.update() do
      Notifier.invitation_confirmed(confirmed)
      {:ok, confirmed}
    end
  end

  def confirm_invitation(%Invitation{} = invitation), do: {:ok, invitation}

  def accept_invitation(%Invitation{status: :accepted} = invitation), do: {:ok, invitation}

  def accept_invitation(%Invitation{} = invitation) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    invitation
    |> Invitation.accept_changeset(now)
    |> Repo.update()
  end
end
