defmodule TuistWeb.Noora.Pages.Colors do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Colors",
    description:
      "The color scales behind every Noora component, and the semantic tokens built from them. Use the semantic tokens in components and layouts: they switch between light and dark through `light-dark()`, so one declaration covers both themes."

  alias TuistWeb.Noora.Tokens

  @semantic [
    {"surfaces", "Surfaces", "Backgrounds for pages, panels, and the overlay behind modals.", ["Background"]},
    {"labels", "Labels", "Text and icon colors, from primary content to disabled states.", ["Label"]},
    {"borders", "Borders", "Strokes that separate regions of a page.", ["Borders"]}
  ]

  def content(assigns) do
    assigns =
      assign(assigns,
        scales: scales() ++ [{"Alpha", alphas()}],
        semantic:
          for {id, title, description, sections} <- @semantic do
            tokens =
              sections
              |> Tokens.section()
              |> Enum.filter(&String.starts_with?(&1.value, "light-dark("))
              |> Enum.uniq_by(& &1.name)

            {id, title, description, tokens}
          end
      )

    ~H"""
    <div id="noora-colors" data-part="color-copy" phx-hook=".NooraColorCopy">
      <section id="palette" data-part="section">
        <h2><a href="#palette">Palette</a></h2>
        <p>Each hue as a scale of steps. Select a swatch to copy its token.</p>
        <div data-part="palette">
          <div :for={{name, tokens} <- @scales} data-part="palette-row">
            <span data-part="palette-name">{name}</span>
            <.color_button
              :for={token <- tokens}
              token={token.name}
              data-part="palette-swatch"
              title={token.name}
            />
          </div>
        </div>
      </section>

      <section :for={{id, title, description, tokens} <- @semantic} id={id} data-part="section">
        <h2><a href={"##{id}"}>{title}</a></h2>
        <p>{description}</p>
        <div data-part="swatches">
          <div :for={token <- tokens} data-part="swatch">
            <.color_button token={token.name} data-part="chip" />
            <code>{token.name}</code>
          </div>
        </div>
      </section>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".NooraColorCopy">
        // Picks the check color with the higher WCAG contrast against what
        // the swatch actually paints: its color composited over the page,
        // so translucent and theme-dependent tokens resolve correctly.
        function checkTone(swatch) {
          const canvas = document.createElement("canvas")
          canvas.width = canvas.height = 1
          const context = canvas.getContext("2d")
          context.fillStyle = getComputedStyle(document.body).backgroundColor
          context.fillRect(0, 0, 1, 1)
          context.fillStyle = getComputedStyle(swatch).backgroundColor
          context.fillRect(0, 0, 1, 1)
          const [r, g, b] = context.getImageData(0, 0, 1, 1).data
          const channel = (value) => {
            const c = value / 255
            return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
          }
          const luminance = 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
          const againstLight = 1.05 / (luminance + 0.05)
          const againstDark = (luminance + 0.05) / 0.05
          return againstLight >= againstDark ? "light" : "dark"
        }

        export default {
          mounted() {
            this.onClick = (event) => {
              const swatch = event.target.closest("[data-token]")
              if (!swatch) return
              navigator.clipboard.writeText(`var(${swatch.dataset.token})`).then(() => {
                swatch.dataset.check = checkTone(swatch)
                swatch.setAttribute("data-copied", "")
                clearTimeout(swatch.copiedTimer)
                swatch.copiedTimer = setTimeout(() => swatch.removeAttribute("data-copied"), 2000)
              })
            }
            this.el.addEventListener("click", this.onClick)
          },
          destroyed() {
            this.el.removeEventListener("click", this.onClick)
          }
        }
      </script>
    </div>
    """
  end

  defp scales do
    "Color palette"
    |> Tokens.section()
    |> Enum.flat_map(fn token ->
      case Regex.run(~r/^--noora-(.+)-(\d+)$/, token.name) do
        # The neutral grays and the alpha tints are translucent: their number
        # is an opacity, not a step, so they appear with the alpha tints.
        [_, "neutral-gray", _opacity] -> []
        [_, "alpha-" <> _, _opacity] -> []
        [_, scale, _step] -> [{scale, token}]
        _ -> []
      end
    end)
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(fn [{scale, _} | _] = chunk -> {humanize(scale), Enum.map(chunk, &elem(&1, 1))} end)
  end

  # The hue tints, then the translucent grays, then black last.
  defp alphas do
    {black, tints} = Enum.split_with(Tokens.prefixed("--noora-alpha-"), &(&1.name == "--noora-alpha-black-80"))
    tints ++ Tokens.prefixed("--noora-neutral-gray-") ++ black
  end

  # "neutral-light" -> "Neutral light"
  defp humanize(scale), do: scale |> String.replace("-", " ") |> String.capitalize()

  attr :token, :string, required: true
  attr :rest, :global

  defp color_button(assigns) do
    ~H"""
    <button
      type="button"
      data-token={@token}
      aria-label={"Copy var(#{@token})"}
      style={"background: var(#{@token})"}
      {@rest}
    >
      <.check />
    </button>
    """
  end
end
