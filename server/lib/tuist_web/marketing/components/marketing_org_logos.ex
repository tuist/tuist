defmodule TuistWeb.Marketing.MarketingOrgLogos do
  @moduledoc ~S"""
  A collection of company logos to include in the marketing pages.

  ## Colored Logo Variants

  For locales that need colored logos (e.g., Korean), create a separate template file
  with the `_color` suffix. For example:
  - `adidas_org_logo.html.heex` - monochrome version (default)
  - `adidas_org_logo_color.html.heex` - colored version

  Then use the colored variant in the page with locale checking:
  ```heex
  <%= if Gettext.get_locale() == "ko" do %>
    <.adidas_org_logo_color />
  <% else %>
    <.adidas_org_logo />
  <% end %>
  ```
  """
  use TuistWeb, :live_component

  embed_templates "marketing_org_logos/*"
end
