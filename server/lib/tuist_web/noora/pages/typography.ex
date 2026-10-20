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
        families: Enum.filter(tokens, &(&1.name in ~w(--noora-font-heading --noora-font-body --noora-font-code))),
        weights: Enum.filter(tokens, &String.starts_with?(&1.name, "--noora-font-weight-")),
        scales:
          for {prefix, title, description} <- @scales do
            {prefix, title, description, Enum.filter(tokens, &String.starts_with?(&1.name, "--noora-font-#{prefix}-"))}
          end
      )

    ~H"""
    <section id="families" data-part="section">
      <h2><a href="#families">Families</a></h2>
      <p>Inter Variable for headings and text, Geist Mono for code.</p>
      <div data-part="token-rows">
        <div :for={token <- @families}>
          <code>{token.name}</code>
          <span data-part="value"></span>
          <span
            data-part="type-specimen"
            style={"font-family: var(#{token.name}); font-size: 1.25rem"}
          >
            The quick brown fox jumps over the lazy dog
          </span>
        </div>
      </div>
    </section>

    <section :for={{prefix, title, description, tokens} <- @scales} id={prefix} data-part="section">
      <h2><a href={"##{prefix}"}>{title}</a></h2>
      <p>{description}</p>
      <div data-part="token-rows">
        <div :for={token <- tokens}>
          <code>{token.name}</code>
          <span data-part="value">{size(token.value)}</span>
          <span
            data-part="type-specimen"
            style={"font: var(--noora-font-weight-medium) var(#{token.name})"}
          >
            {specimen(prefix)}
          </span>
        </div>
      </div>
    </section>

    <section id="weights" data-part="section">
      <h2><a href="#weights">Weights</a></h2>
      <p>Medium for emphasis and controls, semibold for titles.</p>
      <div data-part="token-rows">
        <div :for={token <- @weights}>
          <code>{token.name}</code>
          <span data-part="value">{token.value}</span>
          <span
            data-part="type-specimen"
            style={"font: var(#{token.name}) var(--noora-font-body-large)"}
          >
            Build faster with Tuist
          </span>
        </div>
      </div>
    </section>
    """
  end

  # "2rem/2.375rem var(--noora-font-heading)" -> "32/38"
  defp size(value) do
    case Regex.run(~r/^([\d.]+)rem\/([\d.]+)rem/, value) do
      [_, size, line_height] -> "#{px(size)}/#{px(line_height)}"
      _ -> value
    end
  end

  defp px(rem) do
    {number, ""} = Float.parse(rem)
    number |> Kernel.*(16) |> round() |> Integer.to_string()
  end

  defp specimen("code"), do: "tuist cache --external-only"
  defp specimen(_prefix), do: "Build faster with Tuist"
end
