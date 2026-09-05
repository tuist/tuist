defmodule TuistWeb.Marketing.MarketingIllustrations do
  @moduledoc """
  Inline marketing illustrations (Figma exports, 400x152 wireframes).

  The SVG sources live in `assets/marketing/illustrations/` and are read at
  compile time; their hardcoded greys are rewritten to the marketing
  illustration ramp tokens, so the artwork follows the design tokens (and a
  future dark mode) and its parts can be targeted with CSS for hover
  interactions.
  """
  use Phoenix.Component

  import Phoenix.HTML, only: [raw: 1]

  @illustrations_path Path.expand("../../../../assets/marketing/illustrations", __DIR__)

  # Greys used by the Figma exports -> illustration ramp tokens; window fills
  # and the open-source purple get explicit light/dark pairs.
  @color_tokens %{
    "#E6E8EA" => "var(--marketing-illustration-neutral-2)",
    "#D9DBDD" => "var(--marketing-illustration-neutral-3)",
    "#C9CCCF" => "var(--marketing-illustration-neutral-4)",
    "#EFF0F1" => "var(--marketing-illustration-neutral-1)",
    "#F7F7F7" => "light-dark(var(--noora-neutral-light-100), var(--noora-neutral-dark-1100))",
    "#FDFDFD" => "var(--noora-surface-background-primary)",
    "#6F2CFF" => "light-dark(var(--noora-purple-500), var(--noora-purple-400))",
    "#8366FF" => "light-dark(var(--noora-purple-400), var(--noora-purple-300))"
  }

  # The round SOC badge renders grey (neutral ramp); still used by the
  # footer. The security card uses the shield badge below instead.
  @soc_badge_tokens %{
    "#6F2CFF" => "var(--marketing-illustration-neutral-6)",
    "#8366FF" => "var(--marketing-illustration-neutral-5)"
  }

  # Shield SOC badge (security card): grey outline on the neutral ramp,
  # lettering on purple-400 — the same purple as the OSS logo stroke and
  # the infra cards' highlighted face borders. The hover dither is a
  # DitherTexture canvas clipped to the shield (see marketing_html/new/home.html.heex),
  # not a recolored SVG twin.
  @security_badge_tokens %{
    "#C9CCCF" => "var(--marketing-illustration-neutral-4)",
    "#8B8E91" => "var(--noora-purple-400)"
  }

  # {rendered name, source file, color map}
  @svg_specs Enum.map(
               ~w(cache compute tests transparency-windows transparency-open-source transparency-stacked-faces transparency-stacked-faces-wide),
               &{&1, &1, @color_tokens}
             ) ++
               [
                 {"transparency-soc-badge", "transparency-soc-badge", @soc_badge_tokens},
                 {"security-soc-badge", "security-soc-badge", @security_badge_tokens}
               ]

  @svgs Map.new(@svg_specs, fn {name, file, tokens} ->
          path = Path.join(@illustrations_path, "#{file}.svg")
          Module.put_attribute(__MODULE__, :external_resource, path)

          svg =
            Enum.reduce(tokens, File.read!(path), fn {hex, token}, acc ->
              String.replace(acc, hex, token)
            end)

          {name, svg}
        end)

  attr :name, :string, required: true, values: Map.keys(@svgs)

  def illustration(assigns) do
    assigns = assign(assigns, :svg, Map.fetch!(@svgs, assigns.name))

    ~H"""
    {raw(@svg)}
    """
  end
end
