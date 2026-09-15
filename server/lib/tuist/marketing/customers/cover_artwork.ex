defmodule Tuist.Marketing.Customers.CoverArtwork do
  @moduledoc """
  Generates the SVG cover artwork for customer case studies: the company
  logo centered on a static dither-dot field — the home page customer
  cards' 2px/8px grain, with columns hanging from the top edge and growing
  from the bottom one. The layout is seeded by the case study's slug, so
  every company gets a different pattern that is stable across renders.

  Logos are plain SVG files dropped at
  `priv/marketing/customers/logos/<basename>.svg`, where `<basename>` is
  the case study's markdown file basename (e.g. `monzo.svg` for
  `case_studies/monzo.md`). That single file feeds both surfaces:

    * `svg(basename, :page)` — the card artwork on the marketing site.
      Dots carry `data-fill` attributes so the theme-following CSS rules
      (see marketing_new.css) repaint them per scheme, with light-mode hex
      fallbacks baked in so a copied SVG still renders on its own.
    * `svg(basename, :og)` — the dark variant behind the Open Graph image,
      with the dark-scheme token values baked in because no stylesheet
      travels with a rendered social card.

  Near-black fills in the logo are swapped for `currentColor` at load time
  (the page and the OG wrapper both set the label color on the artwork),
  so wordmarks follow the theme; brand colors pass through untouched.
  """

  @width 352
  @height 198
  # The home card field's grain: 2px dots on an 8px column/row rhythm.
  @pitch 8
  @dot 2
  # Rows a band's columns may grow to (8 rows ≈ 64px deep).
  @band_rows 8
  @logo_height 40

  # Hex values of the tokens the shades resolve to. The page theme paints
  # the light-mode values (the data-fill CSS rules override them in the
  # browser); the OG theme bakes in the dark-mode values
  # (neutral-dark-700/500, purple-400).
  @fills %{
    page: %{"neutral-4" => "#C9CCCF", "neutral-6" => "#A2A5A8", "purple" => "#6F2CFF"},
    og: %{"neutral-4" => "#464646", "neutral-6" => "#717171", "purple" => "#8366FF"}
  }

  @doc """
  Whether cover artwork can be generated for `basename` (a logo file
  exists for it).
  """
  def available?(basename) do
    valid_basename?(basename) and File.regular?(logo_path(basename))
  end

  @doc """
  The complete artwork for `basename` as an SVG string, themed for the
  marketing page (`:page`) or the Open Graph card (`:og`).
  """
  def svg(basename, theme) when theme in [:page, :og] do
    if !available?(basename) do
      raise ArgumentError, "no customer cover logo for #{inspect(basename)}"
    end

    rects =
      Enum.map(dots(basename), fn {x, y, shade} ->
        ~s(<rect x="#{x}" y="#{y}" width="#{@dot}" height="#{@dot}" fill="#{@fills[theme][shade]}"#{data_fill(theme, shade)}/>)
      end)

    IO.iodata_to_binary([
      ~s(<svg data-part="artwork" viewBox="0 0 #{@width} #{@height}" xmlns="http://www.w3.org/2000/svg" fill="none" preserveAspectRatio="xMidYMid slice" aria-hidden="true">),
      rects,
      logo_svg(basename),
      "</svg>"
    ])
  end

  defp data_fill(:page, shade), do: ~s( data-fill="#{shade}")
  defp data_fill(:og, _shade), do: ""

  defp logo_path(basename) do
    Application.app_dir(:tuist, "priv/marketing/customers/logos/#{basename}.svg")
  end

  # Confined to the characters case-study basenames use, which also keeps
  # the interpolation into the priv path traversal-safe.
  defp valid_basename?(basename) when is_binary(basename) do
    basename =~ ~r/^[a-z0-9][a-z0-9-]*$/
  end

  defp valid_basename?(_basename), do: false

  # The logo file re-wrapped as a nested <svg> centered on the canvas at a
  # fixed height, its width following the file's own aspect ratio.
  defp logo_svg(basename) do
    content = basename |> logo_path() |> File.read!()

    [open_tag] = Regex.run(~r/<svg[^>]*>/, content)
    [_, view_width, view_height] = Regex.run(~r/viewBox="0 0 ([\d.]+) ([\d.]+)"/, open_tag)

    inner =
      content
      |> String.split(open_tag, parts: 2)
      |> List.last()
      |> String.split("</svg>")
      |> List.first()
      |> neutralize_dark_fills()

    height = @logo_height
    width = Float.round(height * string_to_number(view_width) / string_to_number(view_height), 2)
    x = Float.round((@width - width) / 2, 2)
    y = Float.round((@height - height) / 2, 2)

    ~s(<svg x="#{x}" y="#{y}" width="#{width}" height="#{height}" viewBox="0 0 #{view_width} #{view_height}" fill="none">#{inner}</svg>)
  end

  # Near-black fills become currentColor so the wordmark follows the theme;
  # anything with enough luma to survive both schemes stays a brand color.
  defp neutralize_dark_fills(svg) do
    Regex.replace(~r/fill="(black|#[0-9a-fA-F]{3}|#[0-9a-fA-F]{6})"/, svg, fn full, color ->
      if dark_color?(color), do: ~s(fill="currentColor"), else: full
    end)
  end

  defp dark_color?("black"), do: true

  defp dark_color?("#" <> hex) do
    hex =
      case String.length(hex) do
        3 -> hex |> String.graphemes() |> Enum.map_join(&(&1 <> &1))
        _ -> hex
      end

    <<red, green, blue>> = Base.decode16!(hex, case: :mixed)
    (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255 < 0.25
  end

  # The dot field: columns hang from the top edge and grow from the bottom
  # one, with random heights, per-dot dropout, and the occasional stray in
  # the middle ground. Seeded by the company so the layout is stable.
  defp dots(seed_term) do
    state =
      :rand.seed_s(
        :exsss,
        {:erlang.phash2({seed_term, 1}), :erlang.phash2({seed_term, 2}), :erlang.phash2({seed_term, 3})}
      )

    columns = Enum.take_every(4..(@width - 4), @pitch)

    {dots, state} = band(columns, :top, [], state)
    {dots, state} = band(columns, :bottom, dots, state)

    {dots, _state} =
      Enum.reduce(columns, {dots, state}, fn x, {acc, state} ->
        stray(x, acc, state)
      end)

    dots
  end

  # A band runs edge to edge: the first and last columns are always active
  # and at most two consecutive columns may stay empty, so the field never
  # opens a hole wider than ~16px, least of all against the card's sides.
  defp band(columns, edge, acc, state) do
    last_x = List.last(columns)

    {acc, _gap, state} =
      Enum.reduce(columns, {acc, 2, state}, fn x, {acc, gap, state} ->
        {activation, state} = :rand.uniform_s(state)

        if activation < 0.55 or gap >= 2 or x == last_x do
          {acc, state} = column(x, edge, acc, state)
          {acc, 0, state}
        else
          {acc, gap + 1, state}
        end
      end)

    {acc, state}
  end

  defp column(x, edge, acc, state) do
    {offset, state} = :rand.uniform_s(state)
    {rows, state} = :rand.uniform_s(state)
    start_row = trunc(offset * 2)
    run = start_row + 1 + trunc(rows * (@band_rows - start_row - 1))

    Enum.reduce(start_row..run//1, {acc, state}, fn row, {acc, state} ->
      {keep, state} = :rand.uniform_s(state)
      {shade, state} = :rand.uniform_s(state)

      if keep < 0.85 do
        {[{x, row_y(edge, row), fill(shade)} | acc], state}
      else
        {acc, state}
      end
    end)
  end

  # A sparse sprinkle between the bands so the middle ground isn't a hard
  # void, like the home field's filler dots.
  defp stray(x, acc, state) do
    {chance, state} = :rand.uniform_s(state)

    if chance < 0.12 do
      {y, state} = :rand.uniform_s(state)
      {shade, state} = :rand.uniform_s(state)
      row = @band_rows + 1 + trunc(y * (@height / @pitch - 2 * @band_rows - 2))
      {[{x, row_y(:top, row), fill(shade)} | acc], state}
    else
      {acc, state}
    end
  end

  defp row_y(:top, row), do: 4 + row * @pitch
  defp row_y(:bottom, row), do: @height - 4 - @dot - row * @pitch

  # Mostly shallow, some mid, the odd purple accent — the shallow/mid split
  # mirrors the home field's shade distribution.
  defp fill(shade) when shade < 0.72, do: "neutral-4"
  defp fill(shade) when shade < 0.95, do: "neutral-6"
  defp fill(_shade), do: "purple"

  defp string_to_number(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> String.to_float(value)
    end
  end
end
