defmodule TuistWeb.Marketing.MarketingFrameworkLogos do
  @moduledoc ~S"""
  Pixel-dithered framework and language logos for the marketing home
  "Built for every stack" grid.

  The SVGs' grey shades are mapped onto the marketing illustration neutral
  ramp (`--marketing-illustration-neutral-1..4`, light to dark), so the logos
  follow the light/dark theme.

  ## Adding New Logos

  1. Add the SVG as `marketing_framework_logos/{name}_framework_logo.html.heex`,
     with fills expressed as illustration-neutral tokens.
  2. Add a `render_logo/1` clause for the name.
  """
  use TuistWeb, :live_component

  embed_templates "marketing_framework_logos/*"

  @doc """
  Renders a framework logo.

  ## Examples

      <.framework_logo name="swift" label="Swift" />
  """
  attr :name, :string, required: true, doc: "The framework name (e.g., 'swift', 'kotlin')"
  attr :label, :string, required: true, doc: "The aria-label for accessibility"

  def framework_logo(assigns) do
    ~H"""
    <div data-part="framework-logo" aria-label={@label}>
      {render_logo(@name)}
    </div>
    """
  end

  defp render_logo("cpp"), do: cpp_framework_logo(%{})
  defp render_logo("dart"), do: dart_framework_logo(%{})
  defp render_logo("go"), do: go_framework_logo(%{})
  defp render_logo("haskell"), do: haskell_framework_logo(%{})
  defp render_logo("java"), do: java_framework_logo(%{})
  defp render_logo("kotlin"), do: kotlin_framework_logo(%{})
  defp render_logo("objc"), do: objc_framework_logo(%{})
  defp render_logo("python"), do: python_framework_logo(%{})
  defp render_logo("rust"), do: rust_framework_logo(%{})
  defp render_logo("scala"), do: scala_framework_logo(%{})
  defp render_logo("swift"), do: swift_framework_logo(%{})
end
