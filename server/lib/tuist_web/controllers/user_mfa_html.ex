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

  defp passkey_details(passkey) do
    added = dgettext("dashboard_auth", "Added %{date}", date: Calendar.strftime(passkey.inserted_at, "%b %-d, %Y"))

    last_used =
      if passkey.last_used_at,
        do: dgettext("dashboard_auth", "last used %{date}", date: Calendar.strftime(passkey.last_used_at, "%b %-d, %Y")),
        else: dgettext("dashboard_auth", "never used")

    # Backup eligibility is fixed at creation: synced passkeys are available
    # on the user's other devices, device-bound ones only on this authenticator.
    storage =
      if passkey.backup_eligible,
        do: dgettext("dashboard_auth", "synced"),
        else: dgettext("dashboard_auth", "this device only")

    Enum.join([added, last_used, storage], " · ")
  end
end
