defmodule TuistWeb.UserMFAHTML do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.SSOLinkHTML, only: [link_frame: 1]

  embed_templates "user_mfa_html/*"

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
