defmodule TuistWeb.Noora.Components do
  @moduledoc """
  The frame and building blocks of the Noora documentation pages.
  """
  use Phoenix.Component
  use Noora

  import TuistWeb.Components.IconComponents, only: [tuist_mark: 1]

  alias Phoenix.LiveView.JS
  alias TuistWeb.Noora.Code
  alias TuistWeb.Noora.Pages

  attr :page, :atom, required: true
  slot :inner_block, required: true

  def docs_shell(assigns) do
    ~H"""
    <div id="noora-docs" class="noora-docs">
      <header data-part="header">
        <div data-part="brand">
          <a href="/" data-part="home" aria-label="Tuist">
            <.tuist_mark aria-hidden="true" />
          </a>
          <span data-part="separator" aria-hidden="true">/</span>
          <.link navigate={Pages.path(Pages.introduction())} data-part="title">Noora</.link>
        </div>
        <div data-part="actions">
          <a
            href="https://github.com/tuist/tuist/tree/main/noora"
            data-part="github"
            aria-label="Noora on GitHub"
          >
            <.brand_github />
          </a>
          <.button_group size="small" id="noora-docs-theme-switcher" phx-hook="ThemeSwitcher">
            <.button_group_item
              icon_only
              data-theme-option="system"
              data-selected
              aria-pressed="true"
              aria-label="System theme"
            >
              <.device_desktop />
            </.button_group_item>
            <.button_group_item
              icon_only
              data-theme-option="light"
              aria-pressed="false"
              aria-label="Light theme"
            >
              <.sun_high />
            </.button_group_item>
            <.button_group_item
              icon_only
              data-theme-option="dark"
              aria-pressed="false"
              aria-label="Dark theme"
            >
              <.moon />
            </.button_group_item>
          </.button_group>
          <button
            type="button"
            data-part="menu-toggle"
            aria-label="Toggle navigation"
            phx-click={JS.toggle_attribute({"data-open", "true"}, to: "#noora-docs")}
          >
            <.menu_2 />
          </button>
        </div>
      </header>
      <div data-part="body">
        <nav id="noora-docs-nav" data-part="sidebar" aria-label="Noora" phx-hook=".NooraDocsSearch">
          <div data-part="search">
            <.search />
            <input
              type="search"
              placeholder="Search"
              aria-label="Search pages"
              autocomplete="off"
              data-part="search-input"
            />
            <kbd>⌘K</kbd>
          </div>
          <div :for={{group, pages} <- Pages.groups()} data-part="group">
            <span data-part="group-title">{group}</span>
            <.link
              :for={page <- pages}
              navigate={Pages.path(page)}
              data-part="nav-item"
              data-selected={page == @page}
              aria-current={if page == @page, do: "page"}
            >
              {page.title()}
            </.link>
          </div>
          <p data-part="search-empty" hidden>No pages match.</p>
        </nav>
        <main data-part="main">
          {render_slot(@inner_block)}
        </main>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".NooraDocsSearch">
        export default {
          mounted() {
            this.input = this.el.querySelector('[data-part="search-input"]')
            this.empty = this.el.querySelector('[data-part="search-empty"]')
            this.onInput = () => this.filter()
            this.onKeydown = (event) => {
              if (event.key === "Enter") {
                const first = this.el.querySelector('[data-part="nav-item"]:not([hidden])')
                if (first) first.click()
              } else if (event.key === "Escape") {
                this.input.value = ""
                this.filter()
                this.input.blur()
              }
            }
            this.onShortcut = (event) => {
              if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
                event.preventDefault()
                this.focus()
              }
            }
            this.input.addEventListener("input", this.onInput)
            this.input.addEventListener("keydown", this.onKeydown)
            window.addEventListener("keydown", this.onShortcut)
          },
          updated() {
            this.filter()
          },
          destroyed() {
            window.removeEventListener("keydown", this.onShortcut)
          },
          focus() {
            document.getElementById("noora-docs").setAttribute("data-open", "true")
            this.input.focus()
            this.input.select()
          },
          filter() {
            const query = this.input.value.trim().toLowerCase()
            let matches = 0
            for (const group of this.el.querySelectorAll('[data-part="group"]')) {
              let visible = 0
              for (const item of group.querySelectorAll('[data-part="nav-item"]')) {
                const match = item.textContent.toLowerCase().includes(query)
                item.hidden = !match
                if (match) visible++
              }
              group.hidden = visible === 0
              matches += visible
            }
            this.empty.hidden = matches > 0
          }
        }
      </script>
    </div>
    """
  end

  attr :page, :atom, required: true
  attr :eyebrow, :string, default: nil

  def docs_page_header(assigns) do
    ~H"""
    <header data-part="page-header">
      <h1>{@page.title()}</h1>
      <p :if={@page.description()} data-part="lede">
        <.rich_text text={@page.description()} />
      </p>
    </header>
    """
  end

  attr :page, :atom, required: true
  attr :example, :map, required: true

  def docs_example(assigns) do
    ~H"""
    <section id={@example.id} class="noora-docs-example" data-part="section">
      <h2>
        <a href={"##{@example.id}"}>{@example.title}</a>
      </h2>
      <p :if={@example.description} data-part="section-description">
        <.rich_text text={@example.description} />
      </p>
      <div data-part="frame">
        <div data-part="preview" data-layout={@example.layout}>
          {apply(@page, @example.function, [%{__changed__: nil}])}
        </div>
        <div data-part="code">
          <.docs_code_window
            id={"#{@example.id}-code"}
            source={@example.source}
            highlighted_source={@example.highlighted_source}
            language="HEEx"
          />
        </div>
        <button
          type="button"
          data-part="code-toggle"
          aria-expanded="false"
          phx-click={
            JS.toggle_attribute({"data-expanded", "true"}, to: "##{@example.id}")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"})
          }
        >
          <span data-part="show">Show code</span>
          <span data-part="hide">Hide code</span>
          <.chevron_down />
        </button>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :source, :string, required: true
  attr :highlighted_source, :string, default: nil
  attr :language, :string, required: true
  attr :highlight_as, :string, default: nil

  def docs_code_window(assigns) do
    assigns =
      assign_new(assigns, :html, fn ->
        assigns.highlighted_source ||
          Code.highlight(assigns.source, assigns.highlight_as || String.downcase(assigns.language))
      end)

    ~H"""
    <div id={@id} class="code-window" phx-hook="CodeCopy">
      <div data-part="bar">
        <div data-part="language">{@language}</div>
        <div data-part="copy" class="noora-neutral-button" data-size="large">
          <span data-part="copy-icon"><.copy /></span>
          <span data-part="copy-check-icon"><.copy_check /></span>
        </div>
      </div>
      <template data-part="copy-source">{@source}</template>
      <div data-part="code">{Phoenix.HTML.raw(@html)}</div>
    </div>
    """
  end

  attr :page, :atom, required: true

  def docs_guidelines(assigns) do
    ~H"""
    <section :if={@page.guidelines() != []} id="guidelines" data-part="section">
      <h2><a href="#guidelines">Guidelines</a></h2>
      <ul data-part="guidelines">
        <li :for={guideline <- @page.guidelines()}><.rich_text text={guideline} /></li>
      </ul>
    </section>
    """
  end

  attr :page, :atom, required: true

  def docs_api_reference(assigns) do
    ~H"""
    <section :if={@page.components() != []} id="api-reference" data-part="section">
      <h2><a href="#api-reference">API reference</a></h2>
      <div :for={{module, function} <- @page.components()} data-part="api">
        <% component = Map.fetch!(module.__components__(), function) %>
        <% {attrs, global} = Enum.split_with(component.attrs, &(&1.type != :global)) %>
        <h3 data-part="api-name"><code>&lt;.{function}&gt;</code></h3>
        <p data-part="api-module"><code>{inspect(module)}.{function}/1</code></p>
        <div :if={attrs != []} data-part="api-table">
          <table>
            <thead>
              <tr>
                <th>Attribute</th>
                <th>Type</th>
                <th>Default</th>
                <th>Description</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={attr <- attrs}>
                <td>
                  <code>{attr.name}</code>
                  <span :if={attr.required} data-part="required">Required</span>
                </td>
                <td><code>{format_type(attr.type)}</code></td>
                <td>
                  <code :if={Keyword.has_key?(attr.opts, :default)}>
                    {inspect(Keyword.get(attr.opts, :default))}
                  </code>
                  <span :if={!Keyword.has_key?(attr.opts, :default)} data-part="none">–</span>
                </td>
                <td>
                  <.rich_text :if={attr.doc} text={attr.doc} />
                  <span :if={Keyword.has_key?(attr.opts, :values)} data-part="values">
                    <code :for={value <- Keyword.get(attr.opts, :values)}>{inspect(value)}</code>
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :for={attr <- global} data-part="api-global">
          Also accepts global attributes<span :if={attr.opts[:include]}>, including <code :for={name <- attr.opts[:include]}>{name}</code></span>.
        </p>
        <div :if={component.slots != []} data-part="api-table">
          <table>
            <thead>
              <tr>
                <th>Slot</th>
                <th>Description</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={slot <- component.slots}>
                <td>
                  <code>{slot_name(slot.name)}</code>
                  <span :if={slot.required} data-part="required">Required</span>
                </td>
                <td>
                  <.rich_text :if={slot.doc} text={slot.doc} />
                  <span :if={slot.attrs != []} data-part="slot-attrs">
                    Attributes: <code :for={slot_attr <- slot.attrs}>{slot_attr.name}</code>
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>
    """
  end

  attr :page, :atom, required: true

  def docs_page_footer(assigns) do
    assigns = assign(assigns, :neighbors, Pages.neighbors(assigns.page))

    ~H"""
    <nav data-part="page-footer" aria-label="Pages">
      <% {previous, next} = @neighbors %>
      <.link :if={previous} navigate={Pages.path(previous)} data-part="previous">
        <span>Previous</span>
        <strong>{previous.title()}</strong>
      </.link>
      <.link :if={next} navigate={Pages.path(next)} data-part="next">
        <span>Next</span>
        <strong>{next.title()}</strong>
      </.link>
    </nav>
    """
  end

  @doc """
  Renders a sentence where text between backticks is shown as code.
  """
  attr :text, :string, required: true

  def rich_text(assigns) do
    assigns =
      assign(
        assigns,
        :parts,
        assigns.text
        |> String.split("`")
        |> Enum.with_index()
        |> Enum.map(fn {part, index} -> {part, rem(index, 2) == 1} end)
      )

    ~H"""
    <%= for {part, code?} <- @parts do %>
      <code :if={code?}>{part}</code><span :if={!code?}>{part}</span>
    <% end %>
    """
  end

  defp format_type({:struct, module}), do: inspect(module)
  defp format_type(type) when is_atom(type), do: Atom.to_string(type)
  defp format_type(type), do: inspect(type)

  defp slot_name(:inner_block), do: "inner_block"
  defp slot_name(name), do: ":#{name}"
end
