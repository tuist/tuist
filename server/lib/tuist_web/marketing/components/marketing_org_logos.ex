defmodule TuistWeb.Marketing.MarketingOrgLogos do
  @moduledoc ~S"""
  A collection of company logos to include in the marketing pages.

  ## Usage

  Use the `org_logo` component with a company name:
  ```heex
  <.org_logo name="adidas" label="Adidas" />
  ```

  This automatically handles locale-based color variants (Korean locale uses colored logos).

  ## Adding New Logos

  1. Add the monochrome SVG as `{company}_org_logo.html.heex`
  2. Add the colored SVG as `{company}_org_logo_color.html.heex`
  """
  use TuistWeb, :live_component

  embed_templates "marketing_org_logos/*"

  @doc """
  Renders an organization logo with automatic locale-based color variant selection.

  ## Examples

      <.org_logo name="adidas" label="Adidas" />
      <.org_logo name="ford" label="Ford" />
  """
  attr :name, :string, required: true, doc: "The company name (e.g., 'adidas', 'ford')"
  attr :label, :string, required: true, doc: "The aria-label for accessibility"

  def org_logo(assigns) do
    assigns = assign(assigns, :variant, logo_variant(assigns.name, Gettext.get_locale()))

    ~H"""
    <div data-part="org-logo" data-variant={@variant} aria-label={@label}>
      {render_logo(@name, @variant)}
    </div>
    """
  end

  # Colour variants keep their brand colours but draw their black ink as
  # currentColor, so the page can pick an ink that shows on both themes
  # (data-variant lets the CSS tell the two apart).
  defp logo_variant(name, "ko") do
    if function_exported?(__MODULE__, String.to_atom("#{name}_org_logo_color"), 1),
      do: "color",
      else: "mono"
  end

  defp logo_variant(_name, _locale), do: "mono"

  defp render_logo(name, "color"), do: apply(__MODULE__, String.to_atom("#{name}_org_logo_color"), [%{}])
  defp render_logo(name, "mono"), do: apply(__MODULE__, String.to_atom("#{name}_org_logo"), [%{}])
end
