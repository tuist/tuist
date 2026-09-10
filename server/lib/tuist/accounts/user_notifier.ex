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

  # Shared transactional chrome, styled after the redesigned marketing site:
  # 600px bordered cards stacked 2px apart on the grey page surface, Inter for copy,
  # Geist Mono for eyebrows, square corners and hairline dividers. Gmail
  # drops the web fonts and falls back to the system sans/mono stacks.
  defp html_email(body, icon_url, title \\ "Email Confirmation", locale \\ "en") do
    """
    <!DOCTYPE html>
    <html lang="#{locale |> String.replace("_", "-") |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()}">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="color-scheme" content="light only" />
        <meta name="supported-color-schemes" content="light only" />
        <title>#{title |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()}</title>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
        <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500&family=Geist+Mono:wght@400&display=swap" rel="stylesheet" />
        <style>
        body {
          margin: 0;
          padding: 0;
          background-color: #F7F7F7;
          color: #191A1B;
          font-family: "Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans Georgian", Helvetica, Arial, sans-serif;
          -webkit-font-smoothing: antialiased;
        }
        .container {
          padding: 40px 40px 8px;
        }
        h1 {
          font-weight: 400;
          font-size: 28px;
          line-height: 34px;
          letter-spacing: -0.01em;
          margin: 0 0 16px 0;
          color: #191A1B;
          text-align: center;
          text-wrap: balance;
        }
        p {
          font-size: 14px;
          line-height: 20px;
          margin: 0 0 16px 0;
          color: #535659;
          text-align: center;
        }
        a {
          color: #6F2CFF;
        }
        .eyebrow {
          font-family: "Geist Mono", "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
          font-size: 12px;
          line-height: 16px;
          letter-spacing: 0.04em;
          text-transform: uppercase;
          color: #535659;
        }
        .button {
          display: inline-block;
          padding: 6px 8px;
          background-color: #6F2CFF;
          border: 1px solid #5F01E5;
          border-radius: 6px;
          color: #FDFDFD !important;
          font-size: 14px;
          line-height: 20px;
          font-weight: 500;
          text-decoration: none;
        }
        .button:hover {
          background-color: #5F01E5;
        }
        footer p {
          font-size: 12px;
          line-height: 16px;
          margin: 0 0 8px 0;
          color: #707478;
        }
        footer a {
          color: #535659;
        }
        @media only screen and (max-width: 640px) {
          .container {
            padding: 32px 20px 8px !important;
          }
        }
        </style>
      </head>
      <body style="margin: 0; padding: 0; background-color: #F7F7F7;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color: #F7F7F7;">
          <tr>
            <td align="center" style="padding: 32px 8px;">
              <table role="presentation" width="600" cellspacing="0" cellpadding="0" border="0" style="width: 100%; max-width: 600px;">
                <tr>
                  <td align="center" style="padding: 28px 40px; border: 1px solid #EFF0F1; background-color: #FDFDFD;">
                    <img src="#{icon_url}" alt="Tuist" width="100" height="40" style="display: block; width: 100px; height: 40px; border: 0;" />
                  </td>
                </tr>
                <tr>
                  <td style="height: 2px; font-size: 0; line-height: 0;"></td>
                </tr>
                <tr>
                  <td style="border: 1px solid #EFF0F1; background-color: #FDFDFD;">
                    #{body}
                  </td>
                </tr>
                <tr>
                  <td style="height: 2px; font-size: 0; line-height: 0;"></td>
                </tr>
                <tr>
                  <td align="center" style="padding: 20px 40px 24px; border: 1px solid #EFF0F1; background-color: #FDFDFD;">
                    <footer>
                      <p>
                        This email was sent by Tuist. By using our services, you agree to our <a href="https://tuist.dev/terms">terms of service</a> and <a href="https://tuist.dev/privacy">privacy policy</a>.
                      </p>
                      <p style="margin: 0;">© Tuist GmbH #{Date.utc_today().year}. All rights reserved.</p>
                    </footer>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
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
  def air_usage_email(user, account, notification) do
    locale = Map.get(user, :preferred_locale) || "en"

    Gettext.with_locale(TuistWeb.Gettext, locale, fn ->
      build_air_usage_email(user, account, notification, locale)
    end)
  end

  defp build_air_usage_email(
         user,
         account,
         %{threshold: threshold, usage: usage, limit: limit, period_start: period_start} = notification,
         locale
       ) do
    runner? = Map.get(notification, :metric) == :runner_minutes
    {title, description} = air_usage_copy(runner?, threshold)
    percentage = div(usage * 100, limit)

    subject =
      if runner? do
        dgettext("dashboard_account", "%{account_name} has reached %{percentage}% of its Air runner limit",
          account_name: account.name,
          percentage: percentage
        )
      else
        dgettext("dashboard_account", "%{account_name} has reached %{percentage}% of its Air limit",
          account_name: account.name,
          percentage: percentage
        )
      end

    usage_label =
      if runner? do
        dgettext("dashboard_account", "%{usage} of %{limit} baseline runner minutes used", usage: usage, limit: limit)
      else
        dgettext("dashboard_account", "%{usage} of %{limit} remote cache hits used", usage: usage, limit: limit)
      end

    date_format =
      if locale in Timex.Gettext.__gettext__(:known_locales), do: "{Mfull} {D}, {YYYY}", else: "{YYYY}-{0M}-{0D}"

    reset_date =
      period_start
      |> Timex.shift(months: 1)
      |> Timex.beginning_of_month()
      |> Timex.lformat!(date_format, locale)

    reset_label = dgettext("dashboard_account", "Your free allowance resets on %{date} (UTC).", date: reset_date)
    billing_url = Environment.app_url(path: "/#{account.name}/billing")
    progress = min(percentage, 100)
    progress_color = if threshold == 100, do: "#E51D01", else: "#6F2CFF"
    metric_label = if runner?, do: "Air runners", else: "Air cache"
    account_name = account.name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    upgrade_label = dgettext("dashboard_account", "Review usage and upgrade")

    pricing_label =
      dgettext("dashboard_account", "Pro includes the same free allowance, with usage-based pricing beyond it.")

    recipient_label =
      dgettext("dashboard_account", "You're receiving this email because you administer this Tuist account.")

    body =
      html_email(
        """
        <div class="container">
          <p class="eyebrow" style="margin: 0 0 20px;">#{account_name} · #{metric_label}</p>
          <h1>#{title}</h1>
          <p>#{description}</p>
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin: 28px 0 28px; border: 1px solid #EFF0F1; background-color: #FDFDFD;">
            <tr>
              <td align="center" style="padding: 28px 24px 24px;">
                <p style="font-size: 44px; line-height: 52px; font-weight: 400; letter-spacing: -0.02em; color: #{progress_color}; margin: 0 0 4px;">#{percentage}%</p>
                <p style="font-size: 14px; line-height: 20px; color: #191A1B; margin: 0 0 20px;">#{usage_label}</p>
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color: #EFF0F1;">
                  <tr>
                    <td width="#{progress}%" style="height: 8px; background-color: #{progress_color}; font-size: 0; line-height: 0;">&nbsp;</td>#{if progress < 100, do: ~s(<td style="height: 8px; font-size: 0; line-height: 0;">&nbsp;</td>), else: ""}
                  </tr>
                </table>
                <p style="font-size: 12px; line-height: 16px; color: #707478; margin: 16px 0 0;">#{reset_label}</p>
              </td>
            </tr>
          </table>
          <p style="margin: 0 0 24px;">
            <a href="#{billing_url}" class="button" style="color: #FDFDFD;">#{upgrade_label}</a>
          </p>
          <p>#{pricing_label}</p>
          <p style="font-size: 12px; line-height: 16px; color: #707478;">#{recipient_label}</p>
        </div>
        """,
        Environment.email_icon_url(),
        title,
        locale
      )

    user.email
    |> build_email(subject, body)
    |> text_body("""
    #{title}

    #{account.name}: #{usage_label} (#{percentage}%).
    #{description}
    #{reset_label}

    #{upgrade_label}: #{billing_url}

    #{pricing_label}
    #{recipient_label}
    """)
  end

  defp air_usage_copy(true, 100) do
    {
      dgettext("dashboard_account", "You've reached your Air runner limit"),
      dgettext(
        "dashboard_account",
        "New runner jobs are paused for this account. Upgrade to Pro to keep running jobs, or wait until your free runner allowance resets."
      )
    }
  end

  defp air_usage_copy(true, _threshold) do
    {
      dgettext("dashboard_account", "You're nearing your Air runner limit"),
      dgettext(
        "dashboard_account",
        "You're getting close to your monthly free runner allowance. Upgrade to Pro before you reach the limit to keep using runners."
      )
    }
  end

  defp air_usage_copy(false, 100) do
    {
      dgettext("dashboard_account", "You've reached your Air limit"),
      dgettext(
        "dashboard_account",
        "Remote cache access is paused for this account. Upgrade to Pro to keep using the cache, or wait until your free allowance resets."
      )
    }
  end

  defp air_usage_copy(false, _threshold) do
    {
      dgettext("dashboard_account", "You're approaching your Air limit"),
      dgettext(
        "dashboard_account",
        "You're getting close to your monthly free allowance. Upgrade to Pro before you reach the limit to keep remote cache access uninterrupted."
      )
    }
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
