defmodule TuistWeb.DocsComponents do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  alias Tuist.Docs.Sidebar

  @group_icons %{
    "Guides" => "category",
    "Tutorials" => "book",
    "Features" => "apps",
    "Integrations" => "asset",
    "Server" => "server",
    "Contributors" => "users",
    "References" => "file_text"
  }

  attr :current_slug, :string, required: true
  attr :headings, :list, required: true
  slot :inner_block, required: true

  def docs_layout(assigns) do
    assigns = assign(assigns, :tree, Sidebar.tree())

    ~H"""
    <main id="docs-page" data-part="docs-page" phx-hook="DocsActivePage" data-current-slug={@current_slug}>
      <section data-part="docs-layout">
        <nav
          id="docs-sidebar"
          data-part="docs-sidebar"
          aria-label="Documentation navigation"
          phx-update="ignore"
        >
          <div :for={group <- @tree} data-part="docs-nav-section">
            <.line_divider />
            <div data-part="docs-content-divider">
              <.icon name={group_icon(group.label)} />
              <span>{group.label}</span>
            </div>
            <.docs_nav_items items={group.items} current_slug={@current_slug} />
          </div>
        </nav>
        <div data-part="docs-content">
          {render_slot(@inner_block)}
        </div>
        <aside data-part="docs-toc" aria-label="Table of contents">
          <.docs_toc :if={@headings != []} headings={@headings} />
        </aside>
      </section>
    </main>
    """
  end

  attr :items, :list, required: true
  attr :current_slug, :string, required: true

  defp docs_nav_items(assigns) do
    ~H"""
    <%= for item <- @items do %>
      <%= if item.items == [] do %>
        <.link patch={"/docs#{item.slug}"} data-part="docs-nav-link">
          <.tab_menu_vertical
            label={item.label}
            data-selected={Sidebar.item_active?(item, @current_slug)}
          />
        </.link>
      <% else %>
        <div
          id={"docs-nav-#{slugify(item.label)}"}
          phx-hook="NooraCollapsible"
          data-open={Sidebar.item_or_children_active?(item, @current_slug)}
        >
          <div data-part="root">
            <%= if item.slug do %>
              <.link patch={"/docs#{item.slug}"} data-part="trigger">
                <.tab_menu_vertical
                  label={item.label}
                  data-selected={Sidebar.item_active?(item, @current_slug)}
                >
                  <:icon_right>
                    <div data-part="indicator">
                      <div data-part="indicator-down"><.chevron_down /></div>
                      <div data-part="indicator-up"><.chevron_up /></div>
                    </div>
                  </:icon_right>
                </.tab_menu_vertical>
              </.link>
            <% else %>
              <.tab_menu_vertical
                label={item.label}
                data-part="trigger"
                data-selected={Sidebar.item_active?(item, @current_slug)}
              >
                <:icon_right>
                  <div data-part="indicator">
                    <div data-part="indicator-down"><.chevron_down /></div>
                    <div data-part="indicator-up"><.chevron_up /></div>
                  </div>
                </:icon_right>
              </.tab_menu_vertical>
            <% end %>
            <div data-part="content">
              <.docs_nav_items items={item.items} current_slug={@current_slug} />
            </div>
          </div>
        </div>
      <% end %>
    <% end %>
    """
  end

  attr :headings, :list, required: true

  defp docs_toc(assigns) do
    ~H"""
    <span data-part="docs-toc-title">On this page</span>
    <ul data-part="docs-toc-list">
      <li :for={heading <- @headings} data-part="docs-toc-item" data-level={heading.level}>
        <a href={"##{heading.id}"}>{heading.text}</a>
      </li>
    </ul>
    """
  end

  defp group_icon(label), do: Map.get(@group_icons, label, "file")

  defp slugify(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
