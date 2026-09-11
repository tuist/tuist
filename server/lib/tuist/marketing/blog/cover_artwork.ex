defmodule Tuist.Marketing.Blog.CoverArtwork do
  @moduledoc """
  Theme-following SVG cover artwork for blog posts, the blog counterpart of
  `Tuist.Marketing.Customers.CoverArtwork`.

  A cover is a plain SVG file dropped at
  `priv/marketing/blog/covers/<basename>.svg`, where `<basename>` is the
  last segment of the post's slug (e.g. `swifterpm.svg` for
  `/blog/2026/07/16/swifterpm`), drawn with the light-scheme values of the
  illustration ramp. That single file feeds both surfaces:

    * `svg(basename, :page)` — the inline artwork on the blog index cards,
      the post hero and the "Read next" cards. Every fill and stroke that
      matches a ramp value keeps its light hex and gains a `data-fill` /
      `data-stroke` attribute, so the theme-following CSS rules (see
      marketing_new.css) repaint it per scheme; the hex fallback keeps a
      copied SVG rendering on its own.
    * `svg(basename, :og)` — the dark variant behind the Open Graph image,
      with the dark-scheme values baked in because no stylesheet travels
      with a rendered social card. Socials only ever see this one.

  Near-black paints become `currentColor` (the page and the OG wrapper both
  set the label color on the artwork) and the page whites follow the
  surface backgrounds (the covers' `#F7F7F7` ground is the tertiary
  surface); anything else passes through untouched. Paints inside `<mask>`
  elements are luminance values, not colors, so they are left alone.
  """

  # Light-scheme hex of the illustration ramp (neutral-light-200…1100) and
  # the purple accent (purple-500), as Figma exports them; the dark side is
  # neutral-dark-1000…100 and purple-400.
  @ramp %{
    "#EFF0F1" => {"neutral-1", "#222222"},
    "#E6E8EA" => {"neutral-2", "#2E2E2E"},
    "#D9DBDD" => {"neutral-3", "#3A3A3A"},
    "#C9CCCF" => {"neutral-4", "#464646"},
    "#B6B9BC" => {"neutral-5", "#585858"},
    "#A2A5A8" => {"neutral-6", "#717171"},
    "#8B8E91" => {"neutral-7", "#8F8F8F"},
    "#707478" => {"neutral-8", "#A4A4A4"},
    "#535659" => {"neutral-9", "#D2D2D2"},
    "#313335" => {"neutral-10", "#E4E4E4"},
    "#6F2CFF" => {"purple", "#8366FF"},
    # Figma files sometimes carry the dark-scheme purple already; it is the
    # same accent.
    "#8366FF" => {"purple", "#8366FF"}
  }

  # The page whites: the primary surface (and the OG wrapper's near-black
  # ground on the social card), and the covers' #F7F7F7 ground, which is
  # the tertiary surface (neutral-light-100 / neutral-dark-1100).
  @surface %{
    "#FDFDFD" => {"surface", "#0E0E0E"},
    "#FFFFFF" => {"surface", "#0E0E0E"},
    "WHITE" => {"surface", "#0E0E0E"},
    "#F7F7F7" => {"surface-tertiary", "#181818"}
  }

  @doc """
  Whether cover artwork exists for `basename`.
  """
  def available?(basename) do
    valid_basename?(basename) and File.regular?(cover_path(basename))
  end

  @doc """
  The last segment of a post's slug, the name its cover file goes by.
  """
  def basename(%{slug: slug}), do: Path.basename(slug)

  @doc """
  The complete artwork for `basename` as an SVG string, themed for the
  marketing page (`:page`) or the Open Graph card (`:og`).
  """
  def svg(basename, theme) when theme in [:page, :og] do
    if !available?(basename) do
      raise ArgumentError, "no blog cover artwork for #{inspect(basename)}"
    end

    basename |> cover_path() |> File.read!() |> transform(theme)
  end

  @doc """
  Re-themes an SVG document's paints for `theme` and wraps its content in
  the artwork's own root element (see the module documentation).
  """
  def transform(content, theme) when is_binary(content) and theme in [:page, :og] do
    [open_tag] = Regex.run(~r/<svg[^>]*>/, content)
    [_, view_box] = Regex.run(~r/viewBox="([^"]+)"/, open_tag)

    inner =
      content
      |> String.split(open_tag, parts: 2)
      |> List.last()
      |> String.split("</svg>")
      |> List.first()
      |> retheme_paints(theme)

    ~s(<svg data-part="artwork" viewBox="#{view_box}" xmlns="http://www.w3.org/2000/svg" fill="none" preserveAspectRatio="xMidYMid slice" aria-hidden="true">#{inner}</svg>)
  end

  # Masks are split out first: their black/white fills are luminance, and
  # re-theming them would punch the wrong holes.
  defp retheme_paints(svg, theme) do
    ~r/<mask\b.*?<\/mask>/s
    |> Regex.split(svg, include_captures: true)
    |> Enum.map_join(fn
      "<mask" <> _ = mask -> mask
      segment -> retheme_segment(segment, theme)
    end)
  end

  defp retheme_segment(svg, theme) do
    Regex.replace(~r/\b(fill|stroke)="(black|white|#[0-9a-fA-F]{3}|#[0-9a-fA-F]{6})"/, svg, fn full, attribute, color ->
      paint(attribute, normalize(color), full, theme)
    end)
  end

  defp paint(attribute, color, full, theme) do
    cond do
      Map.has_key?(@ramp, color) ->
        {shade, dark} = @ramp[color]

        case theme do
          :page -> ~s(#{attribute}="#{color}" data-#{attribute}="#{shade}")
          :og -> ~s(#{attribute}="#{dark}")
        end

      Map.has_key?(@surface, color) ->
        {shade, dark} = @surface[color]

        case theme do
          :page -> ~s(#{attribute}="#{color}" data-#{attribute}="#{shade}")
          :og -> ~s(#{attribute}="#{dark}")
        end

      dark_color?(color) ->
        ~s(#{attribute}="currentColor")

      true ->
        full
    end
  end

  defp normalize("black"), do: "BLACK"
  defp normalize("white"), do: "WHITE"

  defp normalize("#" <> hex) when byte_size(hex) == 3 do
    "#" <> (hex |> String.graphemes() |> Enum.map_join(&(&1 <> &1)) |> String.upcase())
  end

  defp normalize("#" <> hex), do: "#" <> String.upcase(hex)

  defp dark_color?("BLACK"), do: true
  defp dark_color?("WHITE"), do: false

  defp dark_color?("#" <> hex) do
    <<red, green, blue>> = Base.decode16!(hex)
    (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255 < 0.25
  end

  defp cover_path(basename) do
    Application.app_dir(:tuist, "priv/marketing/blog/covers/#{basename}.svg")
  end

  # Confined to the characters post slugs use, which also keeps the
  # interpolation into the priv path traversal-safe.
  defp valid_basename?(basename) when is_binary(basename) do
    basename =~ ~r/^[a-z0-9][a-z0-9-]*$/
  end

  defp valid_basename?(_basename), do: false
end
