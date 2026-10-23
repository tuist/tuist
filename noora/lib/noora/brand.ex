defmodule Noora.Brand do
  @moduledoc """
  The Tuist logo and wordmark as inline SVG components.

  ```elixir
  <.tuist_wordmark />
  <.tuist_logo variant="mono" height={24} />
  ```

  The shapes are read at compile time from `lib/noora/brand`, the color
  assets published at tuist.dev/brand. The colors follow the page's color
  scheme; pass `surface` to pin them on a background that doesn't.

  Tuist trademarks and brand assets must not be modified or used for any
  purpose other than representing Tuist.
  """
  use Phoenix.Component

  @brand_path Path.expand("brand", __DIR__)
  @logo_path Path.join(@brand_path, "tuist-logo.svg")
  @wordmark_path Path.join(@brand_path, "tuist-wordmark.svg")
  @external_resource @logo_path
  @external_resource @wordmark_path

  # In the color assets the mark is filled with the brand purple and the type
  # with the near-black; the components paint those roles from CSS instead.
  @mark_fill "#6F2CFF"

  @parts (for path <- [@logo_path, @wordmark_path], into: %{} do
            parts =
              ~r/<path d="([^"]+)"[^>]*fill="([^"]+)"/
              |> Regex.scan(File.read!(path))
              |> Enum.map(fn [_, d, fill] -> {if(fill == @mark_fill, do: "mark", else: "type"), d} end)

            {Path.basename(path, ".svg"), parts}
          end)

  attr(:variant, :string,
    values: ~w(color mono),
    default: "color",
    doc: "`color` paints the mark in the brand purple. `mono` paints it in the text color, for monochrome layouts."
  )

  attr(:surface, :string,
    values: ~w(auto light dark),
    default: "auto",
    doc:
      "The background the logo sits on. `auto` follows the page's color scheme; `light` and `dark` pin the colors for surfaces that don't."
  )

  attr(:height, :integer, default: 28, doc: "The rendered height in pixels. The logo is square.")
  attr(:rest, :global)

  def tuist_logo(assigns) do
    assigns = assign(assigns, parts: @parts["tuist-logo"], view_box: "0 0 28 28", width: assigns.height)

    brand_svg(assigns)
  end

  attr(:variant, :string,
    values: ~w(color mono),
    default: "color",
    doc:
      "`color` paints the mark in the brand purple and the name in the text color. `mono` paints both in the text color, for monochrome layouts."
  )

  attr(:surface, :string,
    values: ~w(auto light dark),
    default: "auto",
    doc:
      "The background the wordmark sits on. `auto` follows the page's color scheme; `light` and `dark` pin the colors for surfaces that don't."
  )

  attr(:height, :integer, default: 32, doc: "The rendered height in pixels. The width follows the 84:32 aspect ratio.")
  attr(:rest, :global)

  def tuist_wordmark(assigns) do
    assigns =
      assign(assigns,
        parts: @parts["tuist-wordmark"],
        view_box: "0 0 84 32",
        width: round(assigns.height * 84 / 32)
      )

    brand_svg(assigns)
  end

  defp brand_svg(assigns) do
    ~H"""
    <svg
      class="noora-tuist-brand"
      data-variant={@variant}
      data-surface={@surface}
      viewBox={@view_box}
      width={@width}
      height={@height}
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      role="img"
      aria-label="Tuist"
      {@rest}
    >
      <path :for={{part, d} <- @parts} d={d} data-part={part} />
    </svg>
    """
  end
end
