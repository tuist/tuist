defmodule TuistWeb.Noora.Pages.Colors do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Colors",
    description:
      "Use the semantic tokens in components and layouts. They switch between light and dark through `light-dark()`, so a single declaration covers both themes. Reach for the palette only when no semantic token fits."

  alias TuistWeb.Noora.Tokens

  @semantic [
    {"surfaces", "Surfaces", "Backgrounds for pages, panels, and the overlay behind modals.", ["Background"]},
    {"labels", "Labels", "Text and icon colors, from primary content to disabled states.", ["Label"]},
    {"borders", "Borders", "Strokes that separate regions of a page.", ["Borders"]}
  ]

  def content(assigns) do
    assigns =
      assign(assigns,
        semantic:
          for {id, title, description, sections} <- @semantic do
            {id, title, description,
             sections |> Tokens.section() |> Enum.filter(&String.starts_with?(&1.value, "light-dark("))}
          end,
        scales: scales(),
        alphas: Tokens.prefixed("--noora-alpha-")
      )

    ~H"""
    <section :for={{id, title, description, tokens} <- @semantic} id={id} data-part="section">
      <h2><a href={"##{id}"}>{title}</a></h2>
      <p>{description}</p>
      <div data-part="swatches">
        <div :for={token <- tokens} data-part="swatch">
          <div data-part="chip" style={"background: var(#{token.name})"}></div>
          <code>{token.name}</code>
        </div>
      </div>
    </section>

    <section id="palette" data-part="section">
      <h2><a href="#palette">Palette</a></h2>
      <p>The raw scales the semantic tokens are built from.</p>
      <%= for {name, tokens} <- @scales do %>
        <span data-part="scale-name">{name}</span>
        <div data-part="scale">
          <div :for={token <- tokens} style={"background: var(#{token.name})"} title={token.name}>
            <span>{step(token.name)}</span>
          </div>
        </div>
      <% end %>
    </section>

    <section id="alpha" data-part="section">
      <h2><a href="#alpha">Alpha</a></h2>
      <p>Translucent tints for fills on dark surfaces, where a pale tint would glare.</p>
      <div data-part="swatches">
        <div :for={token <- @alphas} data-part="swatch">
          <div data-part="chip" style={"background: var(#{token.name})"}></div>
          <code>{token.name}</code>
        </div>
      </div>
    </section>
    """
  end

  defp scales do
    "Color palette"
    |> Tokens.section()
    |> Enum.flat_map(fn token ->
      case Regex.run(~r/^--noora-(.+)-(\d+)$/, token.name) do
        [_, scale, _step] -> [{scale, token}]
        _ -> []
      end
    end)
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(fn [{scale, _} | _] = chunk -> {scale, Enum.map(chunk, &elem(&1, 1))} end)
  end

  defp step(name), do: name |> String.split("-") |> List.last()
end
