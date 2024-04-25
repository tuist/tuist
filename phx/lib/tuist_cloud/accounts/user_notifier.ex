defmodule TuistCloud.Accounts.UserNotifier do
  @moduledoc """
  A module that sends emails to users.
  """
  import Swoosh.Email

  alias TuistCloud.Mailer
  alias TuistCloud.Environment
  import TuistCloudWeb.Gettext

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Tuist Cloud", Environment.smtp_user_name()})
      |> subject(subject)
      |> html_body(body)

    with {:ok, _metadata} <-
           Mailer.deliver(email,
             tls_options: :tls_certificate_check.options(Environment.smtp_domain())
           ) do
      {:ok, email}
    end
  end

  defp html_email(body) do
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
            font-family: Inter, sans-serif;
            background-color: #1a1a1a;
            margin: 0;
            padding: 0;
            color: #f2f2f2;
            margin-top: 5rem;
          }
          .container {
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
            background-color: #2b2b2b;
            border-radius: 8px;
            box-shadow: 0px 4px 6px rgba(0, 0, 0, 0.1);
          }
          h1 {
            color: #f2f2f2;
          }
          p {
            color: #ccc;
            margin-bottom: 20px;
            font-size: 15px;
          }
          .button {
            display: inline-block;
            padding: 10px 20px;
            background-color: #4f46e5;
            color: #ffffff;
            font-size: 16px;
            border-radius: 4px;
            text-decoration: none;
            transition: background-color 0.3s ease-in-out;
          }
          .button:hover {
            background-color: #4338ca;
          }
        </style>
      </head>
      <body>
        #{body}
      </body>
    </html>
    """
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(
      user.email,
      gettext("Confirmation instructions"),
      html_email("""
          <div class="container">
            <h1>#{gettext("Email confirmation")}</h1>
            <p>
              #{gettext("Welcome! To start using Tuist Cloud, you need to confirm your email address. Please, click the button below:")}
            </p>
            <p>
              <a href="#{url}" class="button">#{gettext("Confirm my account")}</a>
            </p>
            <p>#{gettext("If you did not request this confirmation, ignore this email.")}</p>
          </div>
      """)
    )
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(
      user.email,
      gettext("Reset password instructions"),
      html_email("""
          <div class="container">
            <h1>#{gettext("Reset password instructions")}</h1>
            <p>
              #{gettext("Hola %{email}, you can reset your password by visiting the URL below:", email: user.email)}
            </p>
            <p>
              <a href="#{url}" class="button">#{gettext("Reset my password")}</a>
            </p>
            <p>#{gettext("If you did not request to reset this password, ignore this email.")}</p>
          </div>
      """)
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
