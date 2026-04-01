defmodule TuistWeb.Docs.MarkdownComponents do
  @moduledoc """
  Phoenix components designed for use directly inside documentation
  markdown files. These replace the VitePress/Vue custom elements
  (HomeCards, Badge, etc.) with native Phoenix LiveView components
  that work through HEEx compilation of markdown.
  """
  use Phoenix.Component
  use Noora

  alias Tuist.Docs.Paths

  # Alert ------------------------------------------------------------------

  @doc """
  Wraps Noora's alert for documentation use.

  We can't use `Noora.Alert.alert/1` directly because its `description`
  attribute renders as escaped plain text inside a `<span>`. Markdown
  alert content is rich HTML (paragraphs, links, code) that needs a
  `<div>` and unescaped rendering via `inner_block`.

  Once Noora's alert gains a slot-based description, this wrapper can be
  replaced with a direct `<.alert>` call.
  """
  attr :status, :string,
    values: ~w(information warning error success),
    required: true

  attr :title, :string, required: true
  slot :inner_block, required: true

  def doc_alert(assigns) do
    ~H"""
    <div
      class="noora-alert tuist-admonition"
      data-type="secondary"
      data-status={@status}
      data-size="large"
    >
      <div data-part="icon">
        <.alert_icon status={@status} />
      </div>
      <div data-part="column">
        <span data-part="title">{@title}</span>
        <div data-part="description">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  defp alert_icon(%{status: status} = assigns) when status in ["error", "information"] do
    ~H"<Noora.Icon.alert_circle />"
  end

  defp alert_icon(%{status: "success"} = assigns) do
    ~H"<Noora.Icon.circle_check />"
  end

  defp alert_icon(%{status: "warning"} = assigns) do
    ~H"<Noora.Icon.alert_triangle />"
  end

  # Table ------------------------------------------------------------------

  @doc """
  Wraps a raw HTML `<table>` from markdown with Noora table styling.

  Noora's `Noora.Table` expects structured data via `rows`/`col` slots and
  cannot wrap arbitrary HTML tables. This component applies the same CSS
  class (`noora-table`) to get consistent styling.
  """
  slot :inner_block, required: true

  def doc_table(assigns) do
    ~H"""
    <div class="noora-table">
      {render_slot(@inner_block)}
    </div>
    """
  end

  # Home cards -------------------------------------------------------------

  attr :locale, :string, default: "en"
  slot :inner_block, required: true

  def home_cards(assigns) do
    ~H"""
    <div class="docs-home-cards">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :title, :string, required: true
  attr :details, :string, required: true
  attr :link, :string, required: true
  attr :locale, :string, default: "en"

  def home_card(assigns) do
    href =
      if String.starts_with?(assigns.link, "http") do
        assigns.link
      else
        Paths.public_path(assigns.locale, assigns.link)
      end

    assigns = assign(assigns, :href, href)

    ~H"""
    <a href={@href} class="docs-home-card">
      <div data-part="image">
        <strong>{@title}</strong>
      </div>
      <div data-part="body">
        <p>{@details}</p>
      </div>
    </a>
    """
  end
end
