defmodule AtlasWeb.Oauth.AuthorizeHTML do
  @moduledoc false
  use AtlasWeb, :html
  use Noora

  import AtlasWeb.CoreComponents, only: []

  embed_templates "authorize_html/*"
end
