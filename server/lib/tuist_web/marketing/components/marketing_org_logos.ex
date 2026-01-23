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
    ~H"""
    <div data-part="org-logo" aria-label={@label}>
      {render_logo(@name, Gettext.get_locale())}
    </div>
    """
  end

  defp render_logo(name, "ko") do
    color_func = String.to_atom("#{name}_org_logo_color")

    if function_exported?(__MODULE__, color_func, 1) do
      apply(__MODULE__, color_func, [%{}])
    else
      mono_func = String.to_atom("#{name}_org_logo")
      apply(__MODULE__, mono_func, [%{}])
    end
  end

  defp render_logo(name, _locale) do
    mono_func = String.to_atom("#{name}_org_logo")
    apply(__MODULE__, mono_func, [%{}])
  end
end
