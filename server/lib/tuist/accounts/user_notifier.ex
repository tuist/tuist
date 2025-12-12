defmodule Tuist.Accounts.UserNotifier do
  @moduledoc """
  A module that sends emails to users.
  """
  use Gettext, backend: TuistWeb.Gettext

  import Bamboo.Email

  alias Tuist.Accounts.User
  alias Tuist.Environment
  alias Tuist.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new_email(to: recipient, from: {"Tuist", Environment.mailing_from_address()}, subject: subject, html_body: body)

    email =
      case Environment.mailing_reply_to_address() do
        nil -> email
        reply_to -> put_header(email, "Reply-To", reply_to)
      end

    Mailer.deliver_now!(email)
  end

  defp html_email(body, icon_url) do
    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="color-scheme" content="light only" />
        <meta name="supported-color-schemes" content="light only" />
        <title>Email Confirmation</title>
       <style>
        body {
          margin: 0;
          padding: 0;
          font-family: "Inter", sans-serif;
        }
        .container {
          max-width: 590px;
          margin: 0 auto;
          padding: 20px 40px;
        }
        h1 {
          font-weight: 500;
          font-size: 32px;
          margin: 0 0 20px 0;
          color: #333333;
          text-align: center;
        }
        p {
          font-size: 16px;
          line-height: 24px;
          margin: 0 0 20px 0;
          text-align: center;
        }
        .button {
          display: inline-block;
          padding: 10px 20px;
          background-color: #622ED4;
          font-size: 18px;
          font-weight: 500;
          text-decoration: none;
          border-radius: 8px;
          transition: background-color 0.3s ease-in-out;
        }
        .button:hover {
          background-color: #3c315b;
        }
        footer {
          text-align: center;
          padding: 20px 0;
          color: #999999;
        }
        </style>
      </head>
      <body>
      <div class="header" style="text-align: center; padding: 20px 0;">
      <img class="image" src="#{icon_url}" alt="Tuist Icon" style="width: 75px; height: 75px; display: block; margin: 0 auto;" />
      </div>
        #{body}
      <footer>
      <p style="font-size: 12px">
         This email was sent by Tuist. By using our services, you agree to our <a href="https://tuist.io/terms/"> terms of service</a>.
         <br/>
         © Tuist GmbH 2024. All rights reserved.
      </p>
      </footer>
      </body>
    </html>
    """
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(%{user: user, confirmation_url: confirmation_url}) do
    deliver(
      user.email,
      dgettext("dashboard_account", "Confirmation instructions"),
      html_email(
        """
            <div class="container">
                <h1>#{dgettext("dashboard_account", "You're Almost Set!")}</h1>
                <p>
                  #{dgettext("dashboard_account", "To start using Tuist, verify your email and you are good to go:")}
                </p>
                <p style="padding-top: 16px; padding-bottom: 16px;">
                  <a href="#{confirmation_url}" style="color: #ffffff;" class="button">#{dgettext("dashboard_account", "Confirm your email")}</a>
                </p>
                <p style="font-size: 14px; color: #555555;">
                 #{dgettext("dashboard_account", "You received this email because you recently signed up for a Tuist account.")}
                 <br/>
                 #{dgettext("dashboard_account", "If you didn't make this request, feel free to ignore this email.")}
                </p>
            </div>
        """,
        Environment.email_icon_url()
      )
    )
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(%{user: user, reset_password_url: reset_password_url}) do
    deliver(
      user.email,
      dgettext("dashboard_account", "Reset password instructions"),
      html_email(
        """
            <div class="container">
              <h1>#{dgettext("dashboard_account", "Did you request to reset your password?")}</h1>
              <p>
                #{dgettext("dashboard_account", "Hola %{name}, you can reset your password by clicking the button below:", name: user.account.name)}
              </p>
              <p style="padding-top: 16px; padding-bottom: 16px;">
                <a href="#{reset_password_url}" style="color: #ffffff;" class="button">#{dgettext("dashboard_account", "Reset your password")}</a>
              </p>
              <p style="font-size: 14px; color: #555555; text-align: center;">
                 #{dgettext("dashboard_account", "You received this email because you requested a password reset for your Tuist account.")}
                 <br/>
                 #{dgettext("dashboard_account", "If you didn't make this request, feel free to ignore this email.")}
                </p>
            </div>
        """,
        Environment.email_icon_url()
      )
    )
  end

  @doc """
  Deliver invitation to an organization
  """
  def deliver_invitation(invitee_email, %{
        inviter: %User{email: inviter_email},
        to: %{account: %{name: organization_name}},
        url: url
      }) do
    deliver(
      invitee_email,
      dgettext("dashboard_account", "Invitation to %{organization_name}", organization_name: organization_name),
      html_email(
        """
            <div class="container">
              <h1>#{dgettext("dashboard_account", "You were invited to join the %{organization_name} Tuist organization by %{inviter_email}", organization_name: organization_name, inviter_email: inviter_email)}</h1>
              <p>
                #{dgettext("dashboard_account", "Hola %{invitee_email}, you can join the organization by clicking the button below:", invitee_email: invitee_email)}
              </p>
              <p style="padding-top: 16px; padding-bottom: 16px;">
                <a href="#{url}" style="color: #ffffff;" class="button">#{dgettext("dashboard_account", "Accept invitation")}</a>
              </p>
            </div>
        """,
        Environment.email_icon_url()
      )
    )
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end
end
