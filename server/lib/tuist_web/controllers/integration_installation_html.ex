defmodule TuistWeb.IntegrationInstallationHTML do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.AppAuthComponents

  embed_templates "integration_installation_html/*"
end
