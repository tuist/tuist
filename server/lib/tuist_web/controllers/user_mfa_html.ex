defmodule TuistWeb.UserMFAHTML do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.SSOLinkHTML, only: [link_frame: 1, security_settings_frame: 1]

  embed_templates "user_mfa_html/*"

  def enrollment_qr(secret, email) do
    {:ok, png} =
      "Tuist:#{email}"
      |> NimbleTOTP.otpauth_uri(secret, issuer: "Tuist")
      |> QRCode.create(:medium)
      |> QRCode.render(:png)

    "data:image/png;base64," <> Base.encode64(png)
  end
end
