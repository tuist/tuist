defmodule TuistWeb.Noora.Pages.Typography do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Typography",
    description:
      "Each type token sets the size, line height, and family in one `font` shorthand. Combine it with a weight token: `font: var(--noora-font-weight-medium) var(--noora-font-body-medium)`."

  alias TuistWeb.Noora.Tokens

  @scales [
    {"display", "Display", "For hero headlines on marketing surfaces."},
    {"heading", "Headings", "For page, section, and card titles."},
    {"body", "Body", "For running text, labels, and supporting copy."},
    {"code", "Code", "For code, identifiers, and tabular figures."}
  ]

  def content(assigns) do
    tokens = Tokens.section("Typography")

    assigns =
      assign(assigns,
        families:
          tokens
          |> Enum.filter(&(&1.name in ~w(--noora-font-heading --noora-font-body --noora-font-code)))
          |> Enum.chunk_by(&family_name(&1.value))
          |> Enum.map(&{family_name(hd(&1).value), &1}),
        weights: Enum.filter(tokens, &String.starts_with?(&1.name, "--noora-font-weight-")),
        scales:
          for {prefix, title, description} <- @scales do
            {prefix, title, description, Enum.filter(tokens, &String.starts_with?(&1.name, "--noora-font-#{prefix}-"))}
          end
      )

    ~H"""
    <%!-- Display and heading sizes change at 768px, so the sizes shown are
    measured from the rendered specimens and re-measured on resize. The
    server renders the base sizes as a starting point. --%>
    <div id="noora-typography" data-part="type-sizes" phx-hook=".NooraTypeSizes">
      <section id="families" data-part="section">
        <h2><a href="#families">Families</a></h2>
        <p>Inter Variable for headings and text, Geist Mono for code.</p>
        <div data-part="token-rows">
          <%!-- Tokens that share a family share one specimen cell, like a
          merged cell; their names keep a cell each. --%>
          <div :for={{family, tokens} <- @families} data-part="token-group">
            <span
              data-part="type-specimen"
              style={"font: var(--noora-font-heading-large); font-family: var(#{hd(tokens).name})"}
            >
              {family}
            </span>
            <div data-part="token-names">
              <code :for={token <- tokens} data-part="token-name">{token.name}</code>
            </div>
          </div>
        </div>
      </section>

      <section :for={{prefix, title, description, tokens} <- @scales} id={prefix} data-part="section">
        <h2><a href={"##{prefix}"}>{title}</a></h2>
        <p>{description}</p>
        <div data-part="token-rows">
          <div :for={token <- tokens} data-measure>
            <span
              data-part="type-specimen"
              style={"font: var(--noora-font-weight-medium) var(#{token.name})"}
            >
              {String.capitalize(prefix)} <span data-part="font-size">{font_size(token.value)}</span>
            </span>
            <span data-part="value">{size(token.value)}</span>
            <code data-part="token-name">{token.name}</code>
          </div>
        </div>
      </section>

      <section id="weights" data-part="section">
        <h2><a href="#weights">Weights</a></h2>
        <p>Medium for emphasis and controls, semibold for titles.</p>
        <div data-part="token-rows">
          <div :for={token <- @weights}>
            <span
              data-part="type-specimen"
              style={"font: var(#{token.name}) var(--noora-font-body-large)"}
            >
              {weight_name(token.name)} {token.value}
            </span>
            <span data-part="value">{token.value}</span>
            <code data-part="token-name">{token.name}</code>
          </div>
        </div>
      </section>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".NooraTypeSizes">
        export default {
          mounted() {
            this.measure = this.measure.bind(this)
            window.addEventListener("resize", this.measure)
            document.fonts?.ready.then(this.measure)
            this.measure()
          },
          updated() {
            this.measure()
          },
          destroyed() {
            window.removeEventListener("resize", this.measure)
          },
          measure() {
            for (const row of this.el.querySelectorAll("[data-measure]")) {
              const style = getComputedStyle(row.querySelector('[data-part="type-specimen"]'))
              const size = Math.round(parseFloat(style.fontSize))
              const lineHeight = Math.round(parseFloat(style.lineHeight))
              row.querySelector('[data-part="font-size"]').textContent = size
              row.querySelector('[data-part="value"]').textContent = `${size}/${lineHeight}`
            }
          }
        }
      </script>
    </div>
    """
  end

  # "2rem/2.375rem var(--noora-font-heading)" -> "32/38"
  defp size(value) do
    case Regex.run(~r/^([\d.]+)rem\/([\d.]+)rem/, value) do
      [_, size, line_height] -> "#{px(size)}/#{px(line_height)}"
      _ -> value
    end
  end

  # "2rem/2.375rem var(--noora-font-heading)" -> "32"
  defp font_size(value) do
    case Regex.run(~r/^([\d.]+)rem\//, value) do
      [_, size] -> px(size)
      _ -> ""
    end
  end

  defp px(rem) do
    {number, ""} = Float.parse(rem)
    number |> Kernel.*(16) |> round() |> Integer.to_string()
  end

  # ~s("Inter Variable", "Noto Sans Georgian", sans-serif) -> "Inter Variable"
  defp family_name(value) do
    value |> String.split(",") |> hd() |> String.trim() |> String.trim("\"")
  end

  # "--noora-font-weight-semibold" -> "Semibold"
  defp weight_name(name), do: name |> String.replace_prefix("--noora-font-weight-", "") |> String.capitalize()
end
