defmodule TuistWeb.UserPasskeyHTML do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.SSOLinkHTML, only: [security_settings_frame: 1, reauthentication_notice: 1]

  embed_templates "user_passkey_html/*"
end
