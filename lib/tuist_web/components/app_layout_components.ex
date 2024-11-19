defmodule TuistWeb.AppLayoutComponents do
  @moduledoc ~S"""
  A collection of components that are used from the layouts.
  """
  use TuistWeb, :live_component

  attr :current_path, :string, required: true
  attr :current_user, :map, required: true
  attr :selected_account, :map, required: true
  attr :current_user_accounts, :list, required: true
  attr :can_read_billing, :boolean, required: true

  def account_sidebar(assigns) do
    ~H"""
    <nav class="sidebar">
      <.dropdown_picker
        :if={length(@current_user_accounts) > 0}
        class="sidebar__dropdown"
        menu_id="account-projects"
        menu_class="sidebar__dropdown__menu"
      >
        <%= @selected_account.name %>
        <:content>
          <a :for={account <- @current_user_accounts} href={~p"/#{account.name}/projects"}>
            <%= account.name %>
          </a>
        </:content>
      </.dropdown_picker>
      <ul class="sidebar__navigation-list">
        <% projects_path = ~p"/#{@selected_account.name}/projects" %>
        <li
          class="sidebar__navigation-list__item"
          aria-selected={if projects_path == @current_path, do: "true", else: "false"}
          aria-current={if projects_path == @current_path, do: "page", else: nil}
        >
          <a href={projects_path}>
            <.briefcase_icon />
            <p class="text-md semibold"><%= gettext("Projects") %></p>
          </a>
        </li>
        <%= if @can_read_billing do %>
          <% billing_path = ~p"/#{@selected_account.name}/billing" %>
          <li
            class="sidebar__navigation-list__item"
            aria-selected={if billing_path == @current_path, do: "true", else: "false"}
            aria-current={if billing_path == @current_path, do: "page", else: nil}
          >
            <a href={billing_path}>
              <.credit_card_icon />
              <p class="text-md semibold"><%= gettext("Billing") %></p>
            </a>
          </li>
        <% end %>
      </ul>
    </nav>
    """
  end

  attr :selected_project, :map, required: true
  attr :selected_account, :map, required: true
  attr :current_user, :map, required: true
  attr :current_path, :string, required: true

  def project_sidebar(assigns) do
    ~H"""
    <%= if Map.has_key?(assigns, :selected_account) and !is_nil(@selected_account) and Map.has_key?(assigns, :selected_project) and !is_nil(@selected_project) do %>
      <nav class="sidebar">
        <ul class="sidebar__navigation-list">
          <%= if show_dashboard?() do %>
            <% project_dashboard_path = ~p"/#{@selected_account.name}/#{@selected_project.name}" %>
            <li
              class="sidebar__navigation-list__item"
              aria-selected={if project_dashboard_path == @current_path, do: "true", else: "false"}
              aria-current={if project_dashboard_path == @current_path, do: "page", else: nil}
            >
              <.link patch={project_dashboard_path}>
                <.bar_chart_icon />
                <p class="text-md semibold"><%= gettext("Dashboard") %></p>
              </.link>
            </li>
          <% end %>
          <% runs_path = ~p"/#{@selected_account.name}/#{@selected_project.name}/runs" %>
          <li
            class="sidebar__navigation-list__item"
            aria-selected={if runs_path == @current_path, do: "true", else: "false"}
            aria-current={if runs_path == @current_path, do: "page", else: nil}
          >
            <.link patch={runs_path}>
              <.terminal_square_icon />
              <p class="text-md semibold"><%= gettext("Runs") %></p>
            </.link>
          </li>

          <% tests_path = ~p"/#{@selected_account.name}/#{@selected_project.name}/tests" %>
          <li
            class="sidebar__navigation-list__item"
            aria-selected={if tests_path == @current_path, do: "true", else: "false"}
            aria-current={if tests_path == @current_path, do: "page", else: nil}
          >
            <.link patch={tests_path}>
              <.check_circle_icon />
              <p class="text-md semibold"><%= gettext("Tests") %></p>
            </.link>
          </li>

          <% previews_path = ~p"/#{@selected_account.name}/#{@selected_project.name}/previews" %>
          <li
            class="sidebar__navigation-list__item"
            aria-selected={if previews_path == @current_path, do: "true", else: "false"}
            aria-current={if previews_path == @current_path, do: "page", else: nil}
          >
            <.link patch={previews_path}>
              <.phone_icon />
              <p class="text-md semibold"><%= gettext("Previews") %></p>
            </.link>
          </li>
        </ul>
        <%= if is_nil(@current_user) do %>
          <.link href={~p"/users/log_in"}>
            <.button variant="primary" class="sidebar__sign-in-button">
              <%= gettext("Sign in") %>
            </.button>
          </.link>
        <% end %>
      </nav>
    <% end %>
    """
  end

  attr :breadcrumbs, :list, required: true
  attr :current_user, :map, required: true
  attr :selected_account, :map, required: true
  attr :latest_cli_release, :map, required: false

  def headerbar(assigns) do
    ~H"""
    <header class="headerbar">
      <!-- Logo -->
      <.link navigate={~p"/#{@selected_account.name}/projects"}>
        <img
          src="/images/tuist_logo_32x32@2x.png"
          alt={gettext("Tuist Icon")}
          class="headerbar__logo"
        />
      </.link>
      <!-- Breadcrumbs -->
      <.breadcrumbs breadcrumbs={@breadcrumbs} />
      <!-- Links -->
      <nav class="headerbar__links">
        <a
          :if={latest_cli_release = @latest_cli_release.ok? && @latest_cli_release.result}
          class="headerbar__links__release-badge"
          target="_blank"
          href={latest_cli_release.html_url}
        >
          <.badge title={"#{gettext("New release:")} #{latest_cli_release.name}"} kind={:brand} />
        </a>
        <a class="headerbar__links__link text--small" href="https://docs.tuist.io" target="_blank">
          <.book_open_icon class="headerbar__links__icon" />
          <%= gettext("Documentation") %>
        </a>
      </nav>
      <!-- Avatar -->
      <%= if not is_nil(@current_user) do %>
        <div class="dropdown">
          <% dropdown_class_name = "headerbar__links__avatar__dropdown" %>
          <img
            class="headerbar__links__avatar"
            phx-click={JS.toggle(to: ".#{dropdown_class_name}", display: "flex")}
            phx-window-keydown={JS.hide(to: ".#{dropdown_class_name}")}
            phx-key="Escape"
            src={Tuist.Accounts.User.gravatar_url(@current_user)}
          />
          <div class={dropdown_class_name} hidden phx-click-away={JS.hide()}>
            <div class="headerbar__links__avatar__dropdown__account-email">
              <div class="headerbar__links__avatar__dropdown__account-email-label text--extraSmall">
                Signed as
              </div>
              <div class="headerbar__links__avatar__dropdown__account-email-value text--small">
                <%= @current_user.email %>
              </div>
            </div>
            <hr class="headerbar__links__avatar__dropdown__break" />
            <.link
              href={~p"/users/log_out"}
              method="delete"
              class="headerbar__links__avatar__dropdown__option"
            >
              <.log_out_icon />
              <div class="headerbar__links__avatar__dropdown__option__link text--small">Log out</div>
            </.link>
          </div>
        </div>
      <% end %>
    </header>
    """
  end

  attr :breadcrumbs, :list, required: true

  def breadcrumbs(assigns) do
    ~H"""
    <nav :if={not Enum.empty?(@breadcrumbs)} class="headerbar__breadcrumbs">
      <ol class="headerbar__breadcrumbs__list">
        <%= for {breadcrumb, index} <- Enum.with_index(@breadcrumbs) do %>
          <%= cond do %>
            <% Map.get(breadcrumb, :href) -> %>
              <a href={breadcrumb.href} class="headerbar__breadcrumbs__list-link-item">
                <%= Phoenix.HTML.raw(breadcrumb.content) %>
              </a>
            <% Enum.empty?(Map.get(breadcrumb, :items, []))-> %>
              <span class="headerbar__breadcrumbs__text-item">
                <%= Phoenix.HTML.raw(breadcrumb.content) %>
              </span>
            <% true -> %>
              <.headless_dropdown dropdown_id={"breadcrumbs-item-#{index}-#{breadcrumb.content}"}>
                <:activator :let={attrs}>
                  <div class="headerbar__breadcrumbs__dropdown-item" {attrs}>
                    <%= Phoenix.HTML.raw(breadcrumb.content) %>
                    <.chevron_selector_horizontal class="headerbar__breadcrumbs__dropdown-item__icon" />
                  </div>
                </:activator>
                <div class="headerbar__breadcrumbs__dropdown-item__menu">
                  <a
                    :for={%{content: item_content, href: item_href} <- breadcrumb.items}
                    class="headerbar__breadcrumbs__dropdown-item__menu__item"
                    href={item_href}
                  >
                    <%= item_content %>
                  </a>
                </div>
              </.headless_dropdown>
          <% end %>
          <%= if index != length(@breadcrumbs) - 1 do %>
            <.chevron_right_icon class="headerbar__breadcrumbs__list-chevron" />
          <% end %>
        <% end %>
      </ol>
    </nav>
    """
  end

  def append_breadcrumb(%Phoenix.LiveView.Socket{} = socket, breadcrumb) do
    socket
    |> Phoenix.Component.assign(
      :breadcrumbs,
      Map.get(socket.assigns, :breadcrumbs, []) ++
        [
          breadcrumb
        ]
    )
  end

  defp show_dashboard?() do
    if Tuist.Environment.on_premise?() do
      Tuist.Repo.timescale_available?()
    else
      true
    end
  end
end
