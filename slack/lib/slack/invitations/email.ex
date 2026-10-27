defmodule Slack.Invitations.Email do
  @moduledoc """
  Swoosh emails sent as part of the invitation flow.
  """

  import Swoosh.Email

  alias Slack.Invitations.Invitation

  def confirmation(%Invitation{} = invitation, confirm_url) do
    text_body = """
    Hi,

    Thanks for requesting an invitation to the Tuist Slack workspace.

    Please confirm your email address by visiting the link below:

    #{confirm_url}

    If you did not request this invitation, you can safely ignore this email.

    — The Tuist team
    """

    base_email()
    |> to(invitation.email)
    |> subject("Confirm your Tuist Slack invitation")
    |> text_body(text_body)
  end

  def accepted(%Invitation{} = invitation, invite_url) do
    text_body = """
    Hi,

    Great news — your request to join the Tuist Slack has been accepted!

    Click the link below to join the workspace:

    #{invite_url}

    See you there!

    — The Tuist team
    """

    base_email()
    |> to(invitation.email)
    |> subject("You're in! Join the Tuist Slack")
    |> text_body(text_body)
  end

  defp base_email do
    from = Application.get_env(:slack, :mailer_from, {"Tuist", "hello@tuist.dev"})
    from(new(), from)
  end
end
