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
    recipient |> build_email(subject, body) |> Mailer.deliver_now!()
  end

  # Builds the email envelope without delivering it. Lets callers that need a
  # non-raising delivery (e.g. Oban workers binding the result to `perform/1`)
  # send via `Mailer.deliver_now/1` while sharing the envelope conventions
  # used by every other notifier function in this module.
  defp build_email(recipient, subject, body) do
    email =
      new_email(to: recipient, from: {"Tuist", Environment.mailing_from_address()}, subject: subject, html_body: body)

    case Environment.mailing_reply_to_address() do
      nil -> email
      reply_to -> put_header(email, "Reply-To", reply_to)
    end
  end

  defp html_email(body, icon_url, title \\ "Email Confirmation") do
    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="color-scheme" content="light only" />
        <meta name="supported-color-schemes" content="light only" />
        <title>#{title |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()}</title>
       <style>
        body {
          margin: 0;
          padding: 0;
          font-family: "Inter", "Noto Sans Georgian", sans-serif;
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
         © Tuist GmbH #{Date.utc_today().year}. All rights reserved.
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
    user.email
    |> build_email(
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
    |> Mailer.deliver_now()
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
  Deliver instructions to view an agent registration OTP.
  """
  def deliver_agent_registration_claim_instructions(%{email: email, claim_view_url: claim_view_url}) do
    deliver(
      email,
      "Your Tuist agent sign-in code",
      html_email(
        """
            <div class="container">
              <h1>View your Tuist sign-in code</h1>
              <p>
                An agent is requesting access to Tuist on your behalf.
                Open the secure page below to view the one-time code, then read it back to the agent.
              </p>
              <p style="padding-top: 16px; padding-bottom: 16px;">
                <a href="#{claim_view_url}" style="color: #ffffff;" class="button">View sign-in code</a>
              </p>
              <p style="font-size: 14px; color: #555555; text-align: center;">
                If you did not ask an agent to connect to Tuist, ignore this email.
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
  Notify an existing Tuist user that they were attached to an organization by
  that organization's SCIM provisioning (e.g. Okta). The user did not initiate
  this — the message exists so they can audit the new membership. Removal is
  only possible by an organization admin (in Tuist) or by the identity
  provider de-provisioning the user, so the copy directs the recipient to
  their IdP/IT admin rather than promising a Tuist self-service flow.

  Returns `{:ok, email}` on successful delivery and `{:error, reason}` on
  delivery failure (e.g. SMTP timeout) so the caller — typically an Oban
  worker — can let Oban's retry pipeline pick it up via the standard
  `{:error, _}` return.
  """
  def deliver_scim_organization_attachment(%User{email: user_email}, %{account: %{name: organization_name}}) do
    organization_url = Environment.app_url(path: "/#{organization_name}")

    subject =
      dgettext("dashboard_account", "You were added to the %{organization_name} Tuist organization",
        organization_name: organization_name
      )

    body =
      html_email(
        """
            <div class="container">
              <h1>#{dgettext("dashboard_account", "You were added to the %{organization_name} Tuist organization", organization_name: organization_name)}</h1>
              <p>
                #{dgettext("dashboard_account", "Hi %{user_email}, your account was added to %{organization_name} by your identity provider's automated user provisioning (SCIM).", user_email: user_email, organization_name: organization_name)}
              </p>
              <p>
                #{dgettext("dashboard_account", "If you expected this, no action is needed. You can open the organization here:")}
              </p>
              <p style="padding-top: 16px; padding-bottom: 16px;">
                <a href="#{organization_url}" style="color: #ffffff;" class="button">#{dgettext("dashboard_account", "Open %{organization_name}", organization_name: organization_name)}</a>
              </p>
              <p>
                #{dgettext("dashboard_account", "If this is unexpected, contact your identity provider administrator (the team that manages your single sign-on) to remove this provisioning. An organization admin in Tuist can also remove you from %{organization_name}.", organization_name: organization_name)}
              </p>
            </div>
        """,
        Environment.email_icon_url()
      )

    user_email |> build_email(subject, body) |> Mailer.deliver_now()
  end

  def deliver_air_usage_notification(user, account, notification) do
    user |> air_usage_email(account, notification) |> Mailer.deliver_now()
  end

  @doc """
  Builds an Air usage email for delivery or local preview.
  """
  def air_usage_email(user, account, %{threshold: threshold, usage: usage, limit: limit, period_start: period_start}) do
    {title, description} =
      if threshold == 100 do
        {
          dgettext("dashboard_account", "You've reached your Air limit"),
          dgettext(
            "dashboard_account",
            "Remote cache access is paused for this account. Upgrade to Pro to keep using the cache, or wait until your free allowance resets."
          )
        }
      else
        {
          dgettext("dashboard_account", "You're approaching your Air limit"),
          dgettext(
            "dashboard_account",
            "You're getting close to your monthly free allowance. Upgrade to Pro before you reach the limit to keep remote cache access uninterrupted."
          )
        }
      end

    subject =
      dgettext("dashboard_account", "%{account_name} has reached %{threshold}% of its Air limit",
        account_name: account.name,
        threshold: threshold
      )

    usage_label = dgettext("dashboard_account", "%{usage} of %{limit} remote cache hits used", usage: usage, limit: limit)
    reset_date = period_start |> Timex.shift(months: 1) |> Timex.beginning_of_month() |> Calendar.strftime("%B %-d, %Y")
    reset_label = dgettext("dashboard_account", "Your free allowance resets on %{date} (UTC).", date: reset_date)
    billing_url = Environment.app_url(path: "/#{URI.encode_www_form(account.name)}/billing")
    progress = min(div(usage * 100, limit), 100)
    progress_color = if threshold == 100, do: "#D92D20", else: "#622ED4"
    account_name = account.name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    body =
      html_email(
        """
        <div class="container">
          <p style="font-size: 13px; font-weight: 600; letter-spacing: 1px; color: #622ED4; margin-bottom: 12px;">#{account_name} · AIR</p>
          <h1>#{title}</h1>
          <p style="color: #555555;">#{description}</p>
          <div style="padding: 24px; margin: 28px 0; background-color: #F7F5FD; border: 1px solid #E9E3F5; border-radius: 12px;">
            <p style="font-size: 36px; line-height: 44px; font-weight: 600; color: #{progress_color}; margin-bottom: 8px;">#{progress}%</p>
            <p style="font-size: 14px; color: #333333; margin-bottom: 16px;">#{usage_label}</p>
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="height: 8px; background-color: #E9E3F5; border-radius: 4px; overflow: hidden;">
              <tr><td width="#{progress}%" style="height: 8px; background-color: #{progress_color}; border-radius: 4px;"></td>#{if progress < 100, do: "<td></td>", else: ""}</tr>
            </table>
            <p style="font-size: 13px; color: #666666; margin: 16px 0 0;">#{reset_label}</p>
          </div>
          <p style="padding: 8px 0;">
            <a href="#{billing_url}" style="display: inline-block; padding: 12px 24px; background-color: #622ED4; color: #FFFFFF; font-size: 16px; font-weight: 600; text-decoration: none; border-radius: 8px;">#{dgettext("dashboard_account", "Review usage and upgrade")}</a>
          </p>
          <p style="font-size: 14px; color: #555555;">#{dgettext("dashboard_account", "Pro includes the same free allowance, with usage-based pricing beyond it.")}</p>
          <p style="font-size: 12px; line-height: 18px; color: #777777;">#{dgettext("dashboard_account", "You're receiving this email because you administer this Tuist account.")}</p>
        </div>
        """,
        Environment.email_icon_url(),
        title
      )

    user.email
    |> build_email(subject, body)
    |> text_body("""
    #{title}

    #{account.name}: #{usage_label} (#{progress}%).
    #{description}
    #{reset_label}

    #{dgettext("dashboard_account", "Review usage and upgrade")}: #{billing_url}

    #{dgettext("dashboard_account", "Pro includes the same free allowance, with usage-based pricing beyond it.")}
    #{dgettext("dashboard_account", "You're receiving this email because you administer this Tuist account.")}
    """)
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
