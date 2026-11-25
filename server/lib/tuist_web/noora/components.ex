defmodule TuistWeb.Noora.Components do
  @moduledoc """
  The frame and building blocks of the Noora documentation pages.
  """
  use Phoenix.Component
  use Noora
  use TuistWeb, :verified_routes

  import TuistWeb.AccountDropdown

  alias Phoenix.LiveView.JS
  alias TuistWeb.Noora.Code
  alias TuistWeb.Noora.Pages

  attr :page, :atom, required: true
  attr :current_user, :map, default: nil
  attr :current_path, :string, default: "/noora"
  slot :inner_block, required: true

  def docs_shell(assigns) do
    # The redesign markers are for the Tuist team only.
    assigns = assign(assigns, :team_member, Pages.team_member?(assigns.current_user))

    ~H"""
    <div id="noora-docs" class="noora-docs">
      <header data-part="header">
        <.link navigate={Pages.path(Pages.introduction())} data-part="brand">
          <.noora_logo />
          <span>noora</span>
        </.link>
        <div data-part="actions">
          <a
            href="https://github.com/tuist/tuist/tree/main/noora"
            data-part="github"
            aria-label="Noora on GitHub"
          >
            <.brand_github />
          </a>
          <.button_group size="medium" id="noora-docs-theme-switcher" phx-hook="ThemeSwitcher">
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
          <.button
            :if={is_nil(@current_user)}
            label="Sign in"
            variant="secondary"
            size="medium"
            href={~p"/docs/login?#{%{return_to: @current_path}}"}
          />
          <.account_dropdown
            :if={@current_user}
            id="noora-docs-account-dropdown"
            current_user={@current_user}
            log_out_return_to={@current_path}
            primary_action="dashboard"
            show_theme_switcher={false}
          />
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
        <%!-- Same scroll behavior as the dashboard sidebar: the NooraScrollArea
        hook hides the native scrollbar behind an overlay thumb and fades the
        bottom edge while there is more to scroll. --%>
        <nav id="noora-docs-nav" data-part="sidebar" aria-label="Noora" phx-hook="NooraScrollArea">
          <div id="noora-docs-nav-viewport" data-part="viewport" phx-hook=".NooraDocsSearch">
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
            <div :for={{group, pages} <- Pages.groups(@current_user)} data-part="group">
              <span data-part="group-title">{group}</span>
              <.link
                :for={page <- pages}
                navigate={Pages.path(page)}
                data-part="nav-item"
                data-selected={page == @page}
                aria-current={if page == @page, do: "page"}
              >
                <%!-- No text inside, so the page search, which matches
                items' text, ignores it. --%>
                <span
                  :if={@team_member and Pages.redesigned?(page)}
                  data-part="redesigned-dot"
                  role="img"
                  aria-label="Redesigned"
                  title="Redesigned"
                ></span>
                {page.nav_title()}
              </.link>
            </div>
            <p data-part="search-empty" hidden>No pages match.</p>
          </div>
          <div id="noora-docs-nav-scrollbar" data-part="scrollbar" phx-update="ignore">
            <div data-part="thumb"></div>
          </div>
        </nav>
        <main data-part="main">
          {render_slot(@inner_block)}
        </main>
      </div>
      <%!-- Toasts shown by toast examples stack here:
      the newest in front with older ones peeking behind, expanding into a
      list on hover. --%>
      <ol
        id="noora-docs-toaster"
        data-part="toaster"
        phx-hook=".NooraDocsToaster"
        phx-update="ignore"
        aria-label="Notifications"
        aria-live="polite"
      >
      </ol>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".NooraDocsToaster">
        const DURATION_MS = 4000
        const EXIT_MS = 400
        const GAP = 12
        const PEEK = 14
        const VISIBLE = 3

        export default {
          mounted() {
            this.toasts = []
            this.expanded = false

            this.onTrigger = (event) => {
              const trigger = event.target.closest('[data-part="toast-trigger"]')
              if (!trigger) return
              const template = trigger.parentElement.querySelector('template[data-part="toast-template"]')
              if (template) this.add(template.content.cloneNode(true), template.hasAttribute("data-preserve"))
            }
            this.onDismiss = (event) => {
              const dismiss = event.target.closest('[data-part="dismiss-icon"]')
              if (!dismiss) return
              event.preventDefault()
              event.stopPropagation()
              const toast = this.toasts.find((t) => t.el === dismiss.closest('[data-part="toast-item"]'))
              if (toast) this.remove(toast)
            }
            this.onEnter = () => this.setExpanded(true)
            this.onLeave = () => this.setExpanded(false)

            document.addEventListener("click", this.onTrigger)
            this.el.addEventListener("click", this.onDismiss, true)
            this.el.addEventListener("mouseenter", this.onEnter)
            this.el.addEventListener("mouseleave", this.onLeave)
          },

          destroyed() {
            document.removeEventListener("click", this.onTrigger)
            for (const toast of this.toasts) clearTimeout(toast.timer)
          },

          // A preserved toast never times out; only its dismiss button closes it.
          add(content, preserve) {
            const el = document.createElement("li")
            el.dataset.part = "toast-item"
            el.append(content)
            // Copies of one example would share ids, and the alert's own
            // dismiss command targets the original; the toaster owns both.
            for (const node of el.querySelectorAll("[id]")) node.removeAttribute("id")
            for (const node of el.querySelectorAll("[phx-click]")) node.removeAttribute("phx-click")
            this.el.append(el)

            const toast = { el, preserve, height: el.firstElementChild.offsetHeight, remaining: DURATION_MS }
            this.toasts.unshift(toast)
            this.layout()
            el.offsetHeight
            requestAnimationFrame(() => el.setAttribute("data-mounted", ""))
            if (!this.expanded) this.start(toast)
          },

          active() {
            return this.toasts.filter((t) => !t.removed)
          },

          layout() {
            const toasts = this.active()
            const front = toasts[0]
            let offset = 0
            toasts.forEach((toast, index) => {
              const lift = this.expanded ? offset : index * PEEK
              const scale = this.expanded ? 1 : 1 - index * 0.05
              const height = this.expanded || index === 0 ? toast.height : front.height
              toast.el.style.setProperty("--lift", `${lift}px`)
              toast.el.style.setProperty("--scale", scale)
              toast.el.style.setProperty("--toast-height", `${height}px`)
              toast.el.style.setProperty("--depth", this.expanded ? 0 : index)
              toast.el.style.zIndex = toasts.length - index
              toast.el.toggleAttribute("data-front", index === 0)
              toast.el.toggleAttribute("data-overflow", index >= VISIBLE)
              offset += toast.height + GAP
            })
            const stacked = front ? front.height + Math.min(toasts.length - 1, VISIBLE - 1) * PEEK : 0
            this.el.style.height = `${this.expanded ? Math.max(offset - GAP, 0) : stacked}px`
          },

          setExpanded(expanded) {
            if (expanded && this.active().length === 0) return
            this.expanded = expanded
            this.el.toggleAttribute("data-expanded", expanded)
            for (const toast of this.active()) expanded ? this.pause(toast) : this.start(toast)
            this.layout()
          },

          start(toast) {
            if (toast.preserve) return
            clearTimeout(toast.timer)
            toast.started = Date.now()
            toast.timer = setTimeout(() => this.remove(toast), Math.max(toast.remaining, 0))
          },

          pause(toast) {
            clearTimeout(toast.timer)
            if (toast.started) toast.remaining -= Date.now() - toast.started
          },

          remove(toast) {
            if (toast.removed) return
            toast.removed = true
            clearTimeout(toast.timer)
            toast.el.setAttribute("data-removed", "")
            if (this.active().length === 0) {
              this.expanded = false
              this.el.removeAttribute("data-expanded")
            }
            this.layout()
            setTimeout(() => {
              toast.el.remove()
              this.toasts = this.toasts.filter((t) => t !== toast)
            }, EXIT_MS)
          }
        }
      </script>
      <%!-- Examples render real components but the page keeps no state, so the
      button groups in them are made live here: choosing an item selects it,
      as an app would from its own state. --%>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".NooraDocsPreview">
        export default {
          mounted() {
            this.el.addEventListener("click", (event) => {
              const item = event.target.closest(".noora-button-group-item")
              if (!item || item.disabled || !this.el.contains(item)) return
              const group = item.closest(".noora-button-group")
              for (const sibling of group.querySelectorAll(":scope > .noora-button-group-item")) {
                const selected = sibling === item
                sibling.toggleAttribute("data-selected", selected)
                if (sibling.hasAttribute("aria-pressed")) {
                  sibling.setAttribute("aria-pressed", String(selected))
                }
              }
            })
          },
        }
      </script>
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

  # The mark paints with currentColor, so the header picks its purple per
  # theme. The viewBox is cropped to the mark so it fills the icon box.
  defp noora_logo(assigns) do
    ~H"""
    <svg
      viewBox="149.568 141.696 692.736 692.736"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
    >
      <path
        d="M535.296 322.752V181.056C535.296 170.617 531.149 160.606 523.768 153.224C516.386 145.843 506.375 141.696 495.936 141.696C485.497 141.696 475.486 145.843 468.104 153.224C460.723 160.606 456.576 170.617 456.576 181.056V322.752C456.576 333.191 460.723 343.202 468.104 350.584C475.486 357.965 485.497 362.112 495.936 362.112C506.375 362.112 516.386 357.965 523.768 350.584C531.149 343.202 535.296 333.191 535.296 322.752ZM640.623 399.032L674.079 365.576C681.249 358.152 685.216 348.21 685.127 337.89C685.037 327.57 680.897 317.698 673.6 310.4C666.302 303.102 656.43 298.963 646.11 298.873C635.79 298.784 625.848 302.751 618.424 309.921L584.968 343.377C577.798 350.8 573.831 360.743 573.921 371.063C574.011 381.383 578.15 391.255 585.448 398.552C592.745 405.85 602.617 409.989 612.937 410.079C623.257 410.169 633.2 406.201 640.623 399.032ZM661.248 527.424H802.944C813.383 527.424 823.394 523.277 830.776 515.896C838.157 508.514 842.304 498.503 842.304 488.064C842.304 477.625 838.157 467.614 830.776 460.232C823.394 452.851 813.383 448.704 802.944 448.704H661.248C650.809 448.704 640.798 452.851 633.416 460.232C626.035 467.614 621.888 477.625 621.888 488.064C621.888 498.503 626.035 508.514 633.416 515.896C640.798 523.277 650.809 527.424 661.248 527.424ZM584.968 632.751L618.424 666.207C625.848 673.377 635.79 677.344 646.11 677.255C656.43 677.165 666.302 673.026 673.6 665.728C680.897 658.43 685.037 648.558 685.127 638.238C685.216 627.918 681.249 617.976 674.079 610.552L640.623 577.096C633.2 569.927 623.257 565.959 612.937 566.049C602.617 566.139 592.745 570.278 585.448 577.576C578.15 584.874 574.011 594.745 573.921 605.066C573.831 615.386 577.798 625.328 584.968 632.751ZM456.576 653.376V795.072C456.576 805.511 460.723 815.522 468.104 822.904C475.486 830.285 485.497 834.432 495.936 834.432C506.375 834.432 516.386 830.285 523.768 822.904C531.149 815.522 535.296 805.511 535.296 795.072V653.376C535.296 642.937 531.149 632.926 523.768 625.544C516.386 618.163 506.375 614.016 495.936 614.016C485.497 614.016 475.486 618.163 468.104 625.544C460.723 632.926 456.576 642.937 456.576 653.376ZM351.249 577.096L317.793 610.552C310.623 617.976 306.656 627.918 306.745 638.238C306.835 648.558 310.974 658.43 318.272 665.728C325.57 673.026 335.442 677.165 345.762 677.255C356.082 677.344 366.024 673.377 373.448 666.207L406.904 632.751C414.073 625.328 418.041 615.386 417.951 605.066C417.861 594.745 413.722 584.874 406.424 577.576C399.126 570.278 389.254 566.139 378.934 566.049C368.614 565.959 358.672 569.927 351.249 577.096ZM330.624 448.704H188.928C178.489 448.704 168.478 452.851 161.096 460.232C153.715 467.614 149.568 477.625 149.568 488.064C149.568 498.503 153.715 508.514 161.096 515.896C168.478 523.277 178.489 527.424 188.928 527.424H330.624C341.063 527.424 351.074 523.277 358.456 515.896C365.837 508.514 369.984 498.503 369.984 488.064C369.984 477.625 365.837 467.614 358.456 460.232C351.074 452.851 341.063 448.704 330.624 448.704ZM406.904 343.377L373.448 309.921C366.024 302.751 356.082 298.784 345.762 298.873C335.442 298.963 325.57 303.102 318.272 310.4C310.974 317.698 306.835 327.57 306.745 337.89C306.656 348.21 310.623 358.152 317.793 365.576L351.249 399.032C358.672 406.201 368.614 410.169 378.934 410.079C389.254 409.989 399.126 405.85 406.424 398.552C413.722 391.255 417.861 381.383 417.951 371.063C418.041 360.743 414.073 350.8 406.904 343.377ZM495.936 440.832C502.138 440.832 508.28 442.054 514.011 444.427C519.741 446.801 524.948 450.28 529.334 454.666C533.72 459.052 537.199 464.259 539.573 469.989C541.946 475.72 543.168 481.861 543.168 488.064C543.168 494.267 541.946 500.409 539.573 506.139C537.199 511.869 533.72 517.076 529.334 521.462C524.948 525.848 519.741 529.327 514.011 531.701C508.28 534.074 502.138 535.296 495.936 535.296C489.733 535.296 483.591 534.074 477.861 531.701C472.131 529.327 466.924 525.848 462.538 521.462C458.152 517.076 454.673 511.869 452.299 506.139C449.926 500.409 448.704 494.267 448.704 488.064C448.704 481.861 449.926 475.72 452.299 469.989C454.673 464.259 458.152 459.052 462.538 454.666C466.924 450.28 472.131 446.801 477.861 444.427C483.591 442.054 489.733 440.832 495.936 440.832Z"
        fill="currentColor"
      />
    </svg>
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
        <div
          :if={!@example.toast}
          id={"#{@example.id}-preview"}
          data-part="preview"
          data-layout={@example.layout}
          phx-hook=".NooraDocsPreview"
        >
          {apply(@page, @example.function, [%{__changed__: nil}])}
        </div>
        <%!-- A toast example shows a trigger. Its rendered output waits in a
        template that the docs toaster (.NooraDocsToaster in docs_shell)
        clones into the page's bottom corner on each press. --%>
        <div :if={@example.toast} data-part="preview" data-layout="row">
          <.button label="Show toast" variant="secondary" data-part="toast-trigger" />
          <template data-part="toast-template" data-preserve={@example.toast == :preserve}>
            {apply(@page, @example.function, [%{__changed__: nil}])}
          </template>
        </div>
        <%!-- The example's source: a code window whose bar holds the
        disclosure toggle in place of the language label, so it keeps the
        shared copy button, copied check, and border sweep. Copying works
        without expanding. The toggle ends a copy's confirmation: the sweep
        is an animation on the code box, and revealing the box while the
        copy button is still marked copied would start it late. --%>
        <div
          id={"#{@example.id}-code"}
          class="code-window"
          data-part="source"
          phx-hook="CodeCopy"
        >
          <div data-part="bar">
            <button
              type="button"
              data-part="code-toggle"
              aria-expanded="false"
              aria-controls={"#{@example.id}-source"}
              phx-click={
                JS.toggle_attribute({"data-expanded", "true"}, to: "##{@example.id}")
                |> JS.toggle_attribute({"aria-expanded", "true", "false"})
                |> JS.remove_attribute("data-copied", to: "##{@example.id}-code [data-part='copy']")
              }
            >
              <.chevron_right />
              <span data-part="show">Show code</span>
              <span data-part="hide">Hide code</span>
            </button>
            <div
              data-part="copy"
              class="noora-ghost-button"
              data-variant="secondary"
              data-size="large"
            >
              <span data-part="copy-icon"><.copy /></span>
              <span data-part="copy-check-icon"><.check /></span>
            </div>
          </div>
          <template data-part="copy-source">{@example.source}</template>
          <div id={"#{@example.id}-source"} data-part="code">
            {Phoenix.HTML.raw(@example.highlighted_source)}
          </div>
        </div>
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
        <div data-part="copy" class="noora-ghost-button" data-variant="secondary" data-size="large">
          <span data-part="copy-icon"><.copy /></span>
          <span data-part="copy-check-icon"><.check /></span>
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
        <div :if={attrs != []} data-part="api-table">
          <.table id={"api-#{function}-attributes"} rows={Enum.map(attrs, &Map.put(&1, :id, &1.name))}>
            <:col :let={attr} label="Attribute">
              <.text_cell label={to_string(attr.name)} sublabel={if attr.required, do: "Required"} />
            </:col>
            <:col :let={attr} label="Type">
              <.text_cell label={format_type(attr.type)} />
            </:col>
            <:col :let={attr} label="Default">
              <.text_cell label={
                if Keyword.has_key?(attr.opts, :default),
                  do: inspect(Keyword.get(attr.opts, :default)),
                  else: "–"
              } />
            </:col>
            <:col :let={attr} label="Description">
              <%!-- No Noora cell takes rich content, so this reuses the text
              cell's structure for its padding and type. --%>
              <div data-part="cell" data-type="text">
                <div data-part="api-description">
                  <span :if={attr.doc}><.rich_text text={attr.doc} /></span>
                  <span :if={Keyword.has_key?(attr.opts, :values)} data-part="values">
                    <code :for={value <- Keyword.get(attr.opts, :values)}>{inspect(value)}</code>
                  </span>
                </div>
              </div>
            </:col>
          </.table>
        </div>
        <p :for={attr <- global} data-part="api-global">
          Also accepts global attributes<span :if={attr.opts[:include]}>, including <code :for={name <- attr.opts[:include]}>{name}</code></span>.
        </p>
        <div :if={component.slots != []} data-part="api-table">
          <.table
            id={"api-#{function}-slots"}
            rows={Enum.map(component.slots, &Map.put(&1, :id, &1.name))}
          >
            <:col :let={slot} label="Slot">
              <.text_cell label={slot_name(slot.name)} sublabel={if slot.required, do: "Required"} />
            </:col>
            <:col :let={slot} label="Description">
              <div data-part="cell" data-type="text">
                <div data-part="api-description">
                  <span :if={slot.doc}><.rich_text text={slot.doc} /></span>
                  <span :if={slot.attrs != []} data-part="slot-attrs">
                    Attributes: <code :for={slot_attr <- slot.attrs}>{slot_attr.name}</code>
                  </span>
                </div>
              </div>
            </:col>
          </.table>
        </div>
      </div>
    </section>
    """
  end

  attr :page, :atom, required: true
  attr :current_user, :map, default: nil

  def docs_page_footer(assigns) do
    assigns = assign(assigns, :neighbors, Pages.neighbors(assigns.page, assigns.current_user))

    ~H"""
    <nav data-part="page-footer" aria-label="Pages">
      <% {previous, next} = @neighbors %>
      <.link :if={previous} navigate={Pages.path(previous)} data-part="previous">
        <span>Previous</span>
        <strong>{previous.nav_title()}</strong>
      </.link>
      <.link :if={next} navigate={Pages.path(next)} data-part="next">
        <span>Next</span>
        <strong>{next.nav_title()}</strong>
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
