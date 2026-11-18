defmodule TuistWeb.Oauth.AuthorizeHTML do
  @moduledoc false

  use TuistWeb, :html
  use Noora

  import TuistWeb.SSOLinkHTML, only: [link_frame: 1]

  embed_templates "authorize_html/*"
end
