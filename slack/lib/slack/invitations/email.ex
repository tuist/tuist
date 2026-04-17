defmodule Slack.Invitations.Email do
  @moduledoc """
  Swoosh emails sent as part of the invitation flow.
  """

  import Swoosh.Email

  alias Slack.Invitations.Invitation

  def confirmation(%Invitation{} = invitation, confirm_url) do
    from = Application.get_env(:slack, :mailer_from, {"Tuist", "hello@tuist.dev"})

    text_body = """
    Hi,

    Thanks for requesting an invitation to the Tuist Slack workspace.

    Please confirm your email address by visiting the link below:

    #{confirm_url}

    If you did not request this invitation, you can safely ignore this email.

    — The Tuist team
    """

    new()
    |> to(invitation.email)
    |> from(from)
    |> subject("Confirm your Tuist Slack invitation")
    |> text_body(text_body)
  end
end
