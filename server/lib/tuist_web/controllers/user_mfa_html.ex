defmodule TuistWeb.UserMFAHTML do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  embed_templates "user_mfa_html/*"

  defp setup_qr(secret, email) do
    {:ok, image} =
      "Tuist:#{email}"
      |> NimbleTOTP.otpauth_uri(secret, issuer: "Tuist")
      |> QRCode.create(:medium)
      |> QRCode.render(:svg)
      |> QRCode.to_base64()

    "data:image/svg+xml;base64," <> image
  end
end
