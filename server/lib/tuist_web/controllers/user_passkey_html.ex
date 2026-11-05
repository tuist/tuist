defmodule TuistWeb.UserPasskeyHTML do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.SSOLinkHTML, only: [link_frame: 1]

  embed_templates "user_passkey_html/*"
end
