defmodule Atlas.GTM.Email do
  @moduledoc false

  import Swoosh.Email

  alias Atlas.GTM.Broadcast
  alias Atlas.GTM.Delivery

  def broadcast(%Broadcast{} = broadcast, %Delivery{} = delivery, unsubscribe_url) do
    body_markdown =
      broadcast.body_markdown <>
        "\n\n---\n\n[Unsubscribe from #{broadcast.audience.name}](#{unsubscribe_url})"

    base_email(
      delivery,
      broadcast.from_name,
      broadcast.from_email,
      broadcast.reply_to_email,
      body_markdown
    )
    |> header("List-Unsubscribe", "<#{unsubscribe_url}>")
    |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
  end

  @doc """
  Renders a direct, per-recipient email from the body, sender, and CC addresses
  stored on the delivery.

  Carries no unsubscribe footer and no `List-Unsubscribe` headers: these are
  transactional notices such as a billing or contract change, which the
  recipient cannot opt out of and which are not sent on behalf of an audience.
  """
  def direct(%Delivery{} = delivery) do
    metadata = delivery.metadata || %{}
    defaults = email_defaults()

    base_email(
      delivery,
      metadata["from_name"] || defaults[:from_name],
      metadata["from_email"] || defaults[:from_email],
      metadata["reply_to_email"] || defaults[:reply_to_email],
      metadata["body_markdown"] || ""
    )
    |> maybe_cc(delivery.cc_emails)
  end

  @doc """
  Renders a transactional template from the variables stored on the delivery.

  The newsletter confirmation is sent on behalf of the Tuist marketing site,
  which owns the verification link, so the URL arrives in `data_variables`
  rather than being built here.
  """
  def transactional(%Delivery{} = delivery) do
    template = delivery.metadata["template"]
    variables = delivery.metadata["data_variables"] || %{}

    case template do
      "newsletter-confirmation" -> newsletter_confirmation(delivery, variables["verificationUrl"])
      _other -> {:error, {:unknown_transactional_template, template}}
    end
  end

  defp newsletter_confirmation(delivery, verification_url) do
    defaults = email_defaults()

    body_markdown = """
    Hello,

    Please confirm that you want to receive the Tuist newsletter.

    [Confirm your subscription](#{verification_url})

    If you did not request this, you can ignore this email.
    """

    base_email(
      delivery,
      defaults[:from_name],
      defaults[:from_email],
      defaults[:reply_to_email],
      body_markdown
    )
  end

  def confirmation(%Delivery{} = delivery, confirmation_url) do
    defaults = email_defaults()

    body_markdown = """
    Hello,

    Please confirm that you want to receive the Email Digest.

    [Confirm your subscription](#{confirmation_url})

    If you did not request this, you can ignore this email.
    """

    base_email(
      delivery,
      defaults[:from_name],
      defaults[:from_email],
      defaults[:reply_to_email],
      body_markdown
    )
  end

  def welcome(%Delivery{} = delivery, unsubscribe_url) do
    defaults = email_defaults()
    first_name = delivery.subscriber && delivery.subscriber.first_name
    greeting = if is_binary(first_name) and first_name != "", do: "Hello #{first_name},", else: "Hello,"

    body_markdown = """
    #{greeting}

    Welcome to Tuist. We build tools that help teams make Swift development fast, reliable, and enjoyable at scale.

    You will hear from us when we have something useful to share.

    [Unsubscribe](#{unsubscribe_url})
    """

    base_email(
      delivery,
      defaults[:from_name],
      defaults[:from_email],
      defaults[:reply_to_email],
      body_markdown
    )
    |> header("List-Unsubscribe", "<#{unsubscribe_url}>")
    |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
  end

  defp base_email(delivery, from_name, from_email, reply_to_email, body_markdown) do
    new()
    |> from({from_name, from_email})
    |> to({delivery.recipient_name || "", delivery.recipient_email})
    |> subject(delivery.subject)
    |> text_body(markdown_to_text(body_markdown))
    |> html_body(markdown_to_html(body_markdown))
    |> maybe_reply_to(reply_to_email)
    |> put_provider_option(:idempotency_key, "gtm-delivery-#{delivery.id}")
  end

  @email_font "'Inter Variable', Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
  @email_purple "rgb(111, 44, 255)"
  defp markdown_to_html(markdown) do
    wordmark_url = AtlasWeb.Endpoint.url() <> "/images/tuist_email.png"

    content =
      MDEx.to_html!(markdown,
        extension: [autolink: true, table: true],
        sanitize: MDEx.Document.default_sanitize_options()
      )

    year = Date.utc_today().year

    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="color-scheme" content="light only" />
        <meta name="supported-color-schemes" content="light only" />
        <style>
          @media (prefers-color-scheme: dark) {
            .button-primary {
              background-color: #{@email_purple} !important;
              border-color: #{@email_purple} !important;
              color: #fdfdfd !important;
            }
          }
          [data-ogsc] .button-primary,
          [data-ogsb] .button-primary {
            background-color: #{@email_purple} !important;
            border-color: #{@email_purple} !important;
            color: #fdfdfd !important;
          }
          .broadcast-content h1 { font-weight: 500; font-size: 24px; line-height: 32px; margin: 0 0 16px 0; color: #191a1b; letter-spacing: -0.01em; }
          .broadcast-content h2 { font-weight: 500; font-size: 20px; line-height: 28px; margin: 24px 0 12px 0; color: #191a1b; }
          .broadcast-content p { font-size: 15px; line-height: 24px; margin: 0 0 16px 0; color: #191a1b; }
          .broadcast-content a { color: #{@email_purple}; }
          .broadcast-content ul, .broadcast-content ol { padding-left: 20px; margin: 0 0 16px 0; color: #191a1b; }
          .broadcast-content li { font-size: 15px; line-height: 24px; margin: 0 0 8px 0; }
          .broadcast-content blockquote { margin: 0 0 16px 0; padding: 8px 16px; border-left: 3px solid #eff0f1; color: #535659; }
          .broadcast-content hr { border: none; border-top: 1px solid #eff0f1; margin: 24px 0; }
          .broadcast-content img { max-width: 100%; height: auto; }
          .broadcast-content table { width: 100%; border-collapse: collapse; margin: 0 0 16px 0; }
          .broadcast-content th { font-weight: 500; font-size: 13px; line-height: 20px; text-align: left; padding: 8px 12px; border: 1px solid #eff0f1; background: #f7f7f7; color: #535659; }
          .broadcast-content td { font-size: 15px; line-height: 24px; padding: 8px 12px; border: 1px solid #eff0f1; color: #191a1b; }
        </style>
      </head>
      <body style="margin: 0; padding: 0; background: #f7f7f7; font-family: #{@email_font}; -webkit-font-smoothing: antialiased;">
        <table role="presentation" width="560" align="center" cellpadding="0" cellspacing="0" style="width: 100% !important; max-width: 560px; padding: 24px 8px 40px; box-sizing: border-box;">
          <tr>
            <td>
              <table role="presentation" cellpadding="0" cellspacing="0" style="width: 100%; border: 1px solid #eff0f1; background: #fdfdfd; border-collapse: separate;">
                <tr>
                  <td style="padding: 20px 32px;">
                    <a href="https://tuist.dev" style="display: inline-block; text-decoration: none;">
                      <img src="#{wordmark_url}" alt="Tuist" width="90" height="36" style="display: block; width: 90px; height: 36px; border: 0;" />
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
                    <div class="broadcast-content" style="font-family: #{@email_font};">
                      #{content}
                    </div>
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
                    <p style="margin: 0; font-family: #{@email_font}; font-size: 12px; line-height: 18px; color: #535659;">
                      This email was sent by Tuist. By using our services, you agree to our
                      <a href="https://tuist.dev/terms" style="color: #535659; text-decoration: underline;">terms of service</a>.
                      <br />
                      &copy; Tuist GmbH #{year}. All rights reserved.
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

  defp markdown_to_text(markdown) do
    markdown
    |> String.replace(~r/\[([^\]]+)\]\(([^)]+)\)/, "\\1: \\2")
    |> String.replace(~r/^[#]{1,6}\s+/m, "")
    |> String.replace("**", "")
  end

  defp maybe_reply_to(email, value) when is_binary(value) and value != "", do: reply_to(email, value)
  defp maybe_reply_to(email, _value), do: email

  defp maybe_cc(email, []), do: email
  defp maybe_cc(email, addresses), do: cc(email, Enum.map(addresses, &{"", &1}))

  defp email_defaults, do: Application.get_env(:atlas, :gtm_email, [])
end
