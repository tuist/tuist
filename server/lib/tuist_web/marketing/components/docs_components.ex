defmodule TuistWeb.Marketing.DocsComponents do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  attr :sections, :list, required: true
  attr :current_slug, :string, required: true

  def docs_sidebar(assigns) do
    ~H"""
    <nav data-part="sidebar">
      <div :for={section <- @sections} data-part="section">
        <.docs_section_header
          text={section.text}
          link={Map.get(section, :link)}
          current_slug={@current_slug}
        />
        <ul :if={Map.has_key?(section, :items)} data-part="items">
          <.docs_nav_item
            :for={item <- section.items}
            item={item}
            current_slug={@current_slug}
            depth={0}
          />
        </ul>
      </div>
    </nav>
    """
  end

  attr :headings, :list, required: true

  def docs_toc(assigns) do
    ~H"""
    <aside data-part="docs-toc">
      <div data-part="toc-header">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="20"
          height="20"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <path d="M21 12h-8" /><path d="M21 6H8" /><path d="M21 18h-8" /><path d="M3 6v4c0 1.1.9 2 2 2h3" /><path d="M3 10v6c0 1.1.9 2 2 2h3" />
        </svg>
        <span>On this page</span>
      </div>
      <ul data-part="toc-items">
        <li :for={heading <- @headings} data-part="toc-item">
          <a href={"##{heading.id}"} data-part="toc-link">{heading.text}</a>
        </li>
      </ul>
    </aside>
    """
  end

  attr :text, :string, required: true
  attr :link, :string, default: nil
  attr :current_slug, :string, required: true

  defp docs_section_header(assigns) do
    ~H"""
    <div data-part="section-header">
      <.link :if={@link} href={@link} data-active={to_string(@current_slug == @link)}>
        {@text}
      </.link>
      <span :if={!@link}>{@text}</span>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :current_slug, :string, required: true
  attr :depth, :integer, required: true

  def docs_nav_item(assigns) do
    has_children = Map.has_key?(assigns.item, :items) and assigns.item.items != []
    collapsed = Map.get(assigns.item, :collapsed, false)
    link = Map.get(assigns.item, :link)

    is_active = link != nil and assigns.current_slug == link

    is_child_active =
      has_children and has_active_descendant?(assigns.item, assigns.current_slug)

    assigns =
      assigns
      |> assign(:has_children, has_children)
      |> assign(:collapsed, collapsed)
      |> assign(:link, link)
      |> assign(:is_active, is_active)
      |> assign(:is_child_active, is_child_active)

    ~H"""
    <li data-part="item" data-depth={@depth}>
      <.link
        :if={@link}
        href={@link}
        data-active={to_string(@is_active)}
        data-part="item-link"
      >
        <span>{@item.text}</span>
        <span :if={@has_children} data-part="chevron">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <path d="m6 9 6 6 6-6" />
          </svg>
        </span>
      </.link>
      <span :if={!@link} data-part="item-label">
        <span>{@item.text}</span>
        <span :if={@has_children} data-part="chevron">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <path d="m6 9 6 6 6-6" />
          </svg>
        </span>
      </span>
      <ul
        :if={@has_children and (!@collapsed or @is_active or @is_child_active)}
        data-part="subitems"
      >
        <.docs_nav_item
          :for={child <- @item.items}
          item={child}
          current_slug={@current_slug}
          depth={@depth + 1}
        />
      </ul>
    </li>
    """
  end

  defp has_active_descendant?(item, current_slug) do
    items = Map.get(item, :items, [])

    Enum.any?(items, fn child ->
      child_link = Map.get(child, :link)

      (child_link != nil and current_slug == child_link) or
        has_active_descendant?(child, current_slug)
    end)
  end
end
