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
  # A content map (see html_email/2) is rendered twice: the HTML shell and a
  # plain-text alternative for text-only clients and deliverability filters.
  defp build_email(recipient, subject, %{title: _} = content) do
    build_email(recipient, subject, html_email(content, Environment.email_icon_url()), text_email(content))
  end

  defp build_email(recipient, subject, html) when is_binary(html), do: build_email(recipient, subject, html, nil)

  defp build_email(recipient, subject, html, text) do
    email =
      new_email(to: recipient, from: {"Tuist", Environment.mailing_from_address()}, subject: subject, html_body: html)

    email = if text, do: text_body(email, text), else: email

    case Environment.mailing_reply_to_address() do
      nil -> email
      reply_to -> put_header(email, "Reply-To", reply_to)
    end
  end

  @font "'Inter Variable', Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
  @purple "rgb(111, 44, 255)"

  # Renders a transactional email in the marketing site's design language,
  # within what mail clients allow: tables, inline styles, the palette as
  # hex values (Gmail drops <style> blocks, so only the dark-mode guard for
  # the button lives in one). The same shell as the newsletter issue: a
  # masthead box with the wordmark, one bordered content box on the
  # tertiary ground, and a muted footer box. Every text value is escaped
  # here, so callers pass plain strings (interpolated names, emails).
  # Class rules for the emails that bring their own body HTML (html_email/4).
  @body_styles """
    .container {
      padding: 0;
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
  """

  # The redesigned emails describe their content and let the shell lay it
  # out: a title, paragraphs, an optional button and note.
  defp html_email(%{title: title, paragraphs: paragraphs} = content, icon_url) do
    button = Map.get(content, :button)
    note = Map.get(content, :note)
    # The inbox row's preview line: the first paragraph unless the email
    # names one.
    preheader = Map.get(content, :preheader) || List.first(paragraphs)

    inner = """
                    <h1 style="margin: 0; font-family: #{@font}; font-size: 24px; line-height: 32px; font-weight: 400; letter-spacing: -0.01em; color: #191a1b;">#{escape(title)}</h1>
    #{Enum.map_join(paragraphs, "\n", &paragraph/1)}
    #{button_html(button)}
    #{note_html(note)}
    """

    chrome(title, inner, icon_url, "", "en", preheader)
  end

  # The same content as plain text: title, paragraphs, the button as
  # "label: url", then the note.
  defp text_email(%{title: title, paragraphs: paragraphs} = content) do
    button =
      case Map.get(content, :button) do
        {label, url} -> "#{label}: #{url}"
        nil -> nil
      end

    note =
      case Map.get(content, :note) do
        nil -> nil
        lines when is_list(lines) -> Enum.join(lines, "\n")
        text -> text
      end

    [title, Enum.join(paragraphs, "\n\n"), button, note]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  # Emails that build their own body HTML (the Air usage notifications from
  # #13050) pass it here with its title and locale; they get the same
  # masthead, content box and footer, and the class rules in @body_styles
  # that their markup relies on.
  defp html_email(body, icon_url, title, locale) when is_binary(body) do
    chrome(title, body, icon_url, @body_styles, locale, nil)
  end

  # One shell for both forms: the masthead box with the wordmark, the content
  # box on the tertiary ground, the footer box. Two things keep the design
  # light in every client: the light-only colour-scheme meta, which clients
  # that honour it (Apple Mail, Outlook desktop) use to skip their own dark
  # recolouring; and the .button-primary rules, which pin the button in the
  # clients that ignore the meta and recolour anyway (Gmail on Android,
  # Outlook.com's [data-ogsc]/[data-ogsb]). They cover different clients, so
  # both stay.
  defp chrome(title, inner, icon_url, extra_styles, locale, preheader) do
    year = Date.utc_today().year

    """
    <!DOCTYPE html>
    <html lang="#{String.replace(locale, "_", "-")}">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="color-scheme" content="light only" />
        <meta name="supported-color-schemes" content="light only" />
        <title>#{escape(title)}</title>
        <style>
          @media (prefers-color-scheme: dark) {
            .button-primary {
              background-color: #{@purple} !important;
              border-color: #{@purple} !important;
              color: #fdfdfd !important;
            }
          }
          [data-ogsc] .button-primary,
          [data-ogsb] .button-primary {
            background-color: #{@purple} !important;
            border-color: #{@purple} !important;
            color: #fdfdfd !important;
          }
    #{extra_styles}        </style>
      </head>
      <body style="margin: 0; padding: 0; background: #f7f7f7; font-family: #{@font}; -webkit-font-smoothing: antialiased;">
    #{preheader_html(preheader)}
        <table role="presentation" width="560" align="center" cellpadding="0" cellspacing="0" style="width: 100% !important; max-width: 560px; padding: 24px 8px 40px; box-sizing: border-box;">
          <tr>
            <td>
              <table role="presentation" cellpadding="0" cellspacing="0" style="width: 100%; border: 1px solid #eff0f1; background: #fdfdfd; border-collapse: separate;">
                <tr>
                  <td style="padding: 20px 32px;">
                    <a href="#{escape(Environment.app_url())}" style="display: inline-block; text-decoration: none;">
                      <img src="#{escape(icon_url)}" alt="Tuist" width="90" height="36" style="display: block; width: 90px; height: 36px; border: 0;" />
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="height: 2px; line-height: 2px; font-size: 2px;">&nbsp;</td>
          </tr>
          <tr>
            <td>
              <table role="presentation" cellpadding="0" cellspacing="0" style="width: 100%; border: 1px solid #eff0f1; background: #fdfdfd; border-collapse: separate;">
                <tr>
                  <td style="padding: 40px 32px;">
    #{inner}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="height: 2px; line-height: 2px; font-size: 2px;">&nbsp;</td>
          </tr>
          <tr>
            <td>
              <table role="presentation" cellpadding="0" cellspacing="0" style="width: 100%; border: 1px solid #eff0f1; background: #fdfdfd; border-collapse: separate;">
                <tr>
                  <td style="padding: 20px 32px; text-align: center;">
                    <p style="margin: 0; font-family: #{@font}; font-size: 12px; line-height: 18px; color: #535659;">
                      #{escape(dgettext("dashboard_account", "This email was sent by Tuist. By using our services, you agree to our"))}
                      <a href="#{escape(Environment.app_url(path: "/terms"))}" style="color: #535659; text-decoration: underline;">#{escape(dgettext("dashboard_account", "terms of service"))}</a>.
                      <br />
                      &copy; Tuist GmbH #{year}. #{escape(dgettext("dashboard_account", "All rights reserved."))}
                    </p>
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

  # Hidden from the rendered mail, shown by inboxes as the preview line.
  defp preheader_html(nil), do: ""

  defp preheader_html(text) do
    ~s(<div style="display: none; max-height: 0; overflow: hidden; mso-hide: all;">#{escape(text)}</div>)
  end

  defp paragraph(text) do
    ~s(<p style="margin: 12px 0 0; font-family: #{@font}; font-size: 14px; line-height: 20px; color: #191a1b;">#{escape(text)}</p>)
  end

  defp button_html(nil), do: ""

  defp button_html({label, url}) do
    ~s(<p style="margin: 24px 0 0;"><a class="button-primary" href="#{escape(url)}" style="display: inline-block; font-family: #{@font}; font-size: 14px; line-height: 20px; font-weight: 500; color: #fdfdfd; background: #{@purple}; border: 1px solid #{@purple}; border-radius: 6px; padding: 6px 8px; text-decoration: none;">#{escape(label)}</a></p>)
  end

  defp note_html(nil), do: ""

  defp note_html(lines) when is_list(lines) do
    ~s(<p style="margin: 24px 0 0; font-family: #{@font}; font-size: 14px; line-height: 20px; color: #535659;">#{Enum.map_join(lines, "<br />", &escape/1)}</p>)
  end

  defp note_html(text), do: note_html([text])

  defp escape(value), do: value |> to_string() |> Plug.HTML.html_escape()

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(%{user: user, confirmation_url: confirmation_url}) do
    user.email
    |> build_email(
      dgettext("dashboard_account", "Confirmation instructions"),
      %{
        title: dgettext("dashboard_account", "You're Almost Set!"),
        paragraphs: [dgettext("dashboard_account", "To start using Tuist, verify your email and you are good to go:")],
        button: {dgettext("dashboard_account", "Confirm your email"), confirmation_url},
        note: [
          dgettext("dashboard_account", "You received this email because you recently signed up for a Tuist account."),
          dgettext("dashboard_account", "If you didn't make this request, feel free to ignore this email.")
        ]
      }
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
      %{
        title: dgettext("dashboard_account", "Did you request to reset your password?"),
        paragraphs: [
          dgettext("dashboard_account", "Hola %{name}, you can reset your password by clicking the button below:",
            name: user.account.name
          )
        ],
        button: {dgettext("dashboard_account", "Reset your password"), reset_password_url},
        note: [
          dgettext(
            "dashboard_account",
            "You received this email because you requested a password reset for your Tuist account."
          ),
          dgettext("dashboard_account", "If you didn't make this request, feel free to ignore this email.")
        ]
      }
    )
  end

  @doc """
  Deliver instructions to view an agent registration OTP.
  """
  def deliver_agent_registration_claim_instructions(%{email: email, claim_view_url: claim_view_url}) do
    deliver(
      email,
      "Your Tuist agent sign-in code",
      %{
        title: "View your Tuist sign-in code",
        paragraphs: [
          "An agent is requesting access to Tuist on your behalf. Open the secure page below to view the one-time code, then read it back to the agent."
        ],
        button: {"View sign-in code", claim_view_url},
        note: "If you did not ask an agent to connect to Tuist, ignore this email."
      }
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
      %{
        title:
          dgettext(
            "dashboard_account",
            "You were invited to join the %{organization_name} Tuist organization by %{inviter_email}",
            organization_name: organization_name,
            inviter_email: inviter_email
          ),
        paragraphs: [
          dgettext(
            "dashboard_account",
            "Hola %{invitee_email}, you can join the organization by clicking the button below:",
            invitee_email: invitee_email
          )
        ],
        button: {dgettext("dashboard_account", "Accept invitation"), url}
      }
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
      %{
        title: subject,
        paragraphs: [
          dgettext(
            "dashboard_account",
            "Hi %{user_email}, your account was added to %{organization_name} by your identity provider's automated user provisioning (SCIM).",
            user_email: user_email,
            organization_name: organization_name
          ),
          dgettext(
            "dashboard_account",
            "If you expected this, no action is needed. You can open the organization here:"
          )
        ],
        button:
          {dgettext("dashboard_account", "Open %{organization_name}", organization_name: organization_name),
           organization_url},
        note:
          dgettext(
            "dashboard_account",
            "If this is unexpected, contact your identity provider administrator (the team that manages your single sign-on) to remove this provisioning. An organization admin in Tuist can also remove you from %{organization_name}.",
            organization_name: organization_name
          )
      }

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
    deliver(
      user.email,
      dgettext("dashboard_account", "Update email instructions"),
      %{
        title: dgettext("dashboard_account", "Update your email"),
        paragraphs: [
          dgettext("dashboard_account", "Hi %{email}, you can change your email by clicking the button below:",
            email: user.email
          )
        ],
        button: {dgettext("dashboard_account", "Update your email"), url},
        note: dgettext("dashboard_account", "If you didn't request this change, please ignore this email.")
      }
    )
  end
end
