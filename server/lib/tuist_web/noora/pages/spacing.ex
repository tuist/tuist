defmodule TuistWeb.Noora.Pages.Spacing do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Spacing",
    description:
      "One scale for padding, gaps, and margins. Prefer `gap` on flex and grid containers over margins between siblings."

  alias TuistWeb.Noora.Tokens

  def content(assigns) do
    assigns = assign(assigns, tokens: Tokens.section("Spacing"))

    ~H"""
    <section id="scale" data-part="section">
      <h2><a href="#scale">Scale</a></h2>
      <div data-part="token-rows">
        <div :for={token <- @tokens}>
          <code>{token.name}</code>
          <span data-part="value">{token.value}</span>
          <div data-part="spacing-bar" style={"width: var(#{token.name})"}></div>
        </div>
      </div>
    </section>
    """
  end
end
