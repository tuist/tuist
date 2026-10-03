defmodule Atlas.Accounts.POCs.VerificationEmail do
  @moduledoc false

  @font "'Inter Variable', Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
  @purple "rgb(111, 44, 255)"

  def render(brand, url) do
    title = "Verify your email to open the #{brand} brief"
    preview = "Confirm your email to request access to the #{brand} brief."
    wordmark_url = AtlasWeb.Endpoint.url() <> "/images/tuist_email.png"
    year = Date.utc_today().year

    """
    <!DOCTYPE html>
    <html lang="en">
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
        </style>
      </head>
      <body style="margin: 0; padding: 0; background: #f7f7f7; font-family: #{@font}; -webkit-font-smoothing: antialiased;">
        <div style="display: none; max-height: 0; overflow: hidden; mso-hide: all;">#{escape(preview)}</div>
        <table role="presentation" width="560" align="center" cellpadding="0" cellspacing="0" style="width: 100% !important; max-width: 560px; padding: 24px 8px 40px; box-sizing: border-box;">
          <tr>
            <td>
              <table role="presentation" cellpadding="0" cellspacing="0" style="width: 100%; border: 1px solid #eff0f1; background: #fdfdfd; border-collapse: separate;">
                <tr>
                  <td style="padding: 20px 32px;">
                    <a href="https://tuist.dev" style="display: inline-block; text-decoration: none;">
                      <img src="#{escape(wordmark_url)}" alt="Tuist" width="90" height="36" style="display: block; width: 90px; height: 36px; border: 0;" />
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr><td style="height: 2px; line-height: 2px; font-size: 2px;">&nbsp;</td></tr>
          <tr>
            <td>
              <table role="presentation" cellpadding="0" cellspacing="0" style="width: 100%; border: 1px solid #eff0f1; background: #fdfdfd; border-collapse: separate;">
                <tr>
                  <td style="padding: 40px 32px;">
                    <h1 style="margin: 0; font-family: #{@font}; font-size: 24px; line-height: 32px; font-weight: 400; letter-spacing: -0.01em; color: #191a1b;">#{escape(title)}</h1>
                    <p style="margin: 12px 0 0; font-family: #{@font}; font-size: 14px; line-height: 20px; color: #191a1b;">You (or someone using your email) asked to open the #{escape(brand)} brief on Tuist.</p>
                    <p style="margin: 12px 0 0; font-family: #{@font}; font-size: 14px; line-height: 20px; color: #191a1b;">Confirm the request within 15 minutes:</p>
                    <p style="margin: 24px 0 0;"><a class="button-primary" href="#{escape(url)}" style="display: inline-block; font-family: #{@font}; font-size: 14px; line-height: 20px; font-weight: 500; color: #fdfdfd; background: #{@purple}; border: 1px solid #{@purple}; border-radius: 6px; padding: 6px 8px; text-decoration: none;">Confirm my email</a></p>
                    <p style="margin: 24px 0 0; font-family: #{@font}; font-size: 14px; line-height: 20px; color: #535659;">Or paste this link into your browser:<br /><a href="#{escape(url)}" style="color: #6f2cff; overflow-wrap: anywhere; word-break: break-all;">#{escape(url)}</a></p>
                    <p style="margin: 24px 0 0; font-family: #{@font}; font-size: 14px; line-height: 20px; color: #535659;">If you did not request this, you can safely ignore this email.</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr><td style="height: 2px; line-height: 2px; font-size: 2px;">&nbsp;</td></tr>
          <tr>
            <td>
              <table role="presentation" cellpadding="0" cellspacing="0" style="width: 100%; border: 1px solid #eff0f1; background: #fdfdfd; border-collapse: separate;">
                <tr>
                  <td style="padding: 20px 32px; text-align: center;">
                    <p style="margin: 0; font-family: #{@font}; font-size: 12px; line-height: 18px; color: #535659;">
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

  defp escape(value), do: value |> to_string() |> Plug.HTML.html_escape()
end
