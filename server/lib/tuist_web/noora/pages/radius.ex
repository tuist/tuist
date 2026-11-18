defmodule TuistWeb.Noora.Pages.Radius do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Radius"

  alias TuistWeb.Noora.Tokens

  def content(assigns) do
    assigns = assign(assigns, tokens: Tokens.section("Radius"))

    ~H"""
    <section id="scale" data-part="section">
      <div data-part="radius-tiles">
        <div :for={token <- @tokens}>
          <div data-part="tile" style={"border-radius: var(#{token.name})"}></div>
          <code>{token.name}</code>
          <span data-part="value">{token.value}</span>
        </div>
      </div>
    </section>
    """
  end
end
