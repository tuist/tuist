defmodule TuistWeb.Noora.Pages.Borders do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Borders",
    description:
      "Noora draws borders as layered `box-shadow` tokens, so a single declaration adds the outline, depth, and focus ring without changing an element's size. They switch with the theme through `[data-theme]`."

  alias TuistWeb.Noora.Tokens

  def content(assigns) do
    assigns =
      assign(assigns,
        tokens:
          "Borders"
          |> Tokens.section()
          |> Enum.reject(&String.starts_with?(&1.value, "light-dark("))
          |> Enum.uniq_by(& &1.name)
          # Left out for now.
          |> Enum.reject(&(&1.name == "--noora-border-section"))
      )

    ~H"""
    <section id="tokens" data-part="section">
      <h2><a href="#tokens">Tokens</a></h2>
      <div data-part="elevation-tiles">
        <div :for={token <- @tokens}>
          <div data-part="tile" style={"box-shadow: var(#{token.name})"}></div>
          <code>{token.name}</code>
        </div>
      </div>
    </section>
    """
  end
end
