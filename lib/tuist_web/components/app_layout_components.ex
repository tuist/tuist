defmodule TuistWeb.AppLayoutComponents do
  @moduledoc ~S"""
  A collection of components that are used from the layouts.
  """
  use TuistWeb, :live_component
  use TuistWeb.Noora
  import TuistWeb.AppComponents, except: [icon: 1]
  import TuistWeb.AccountDropdown
  import TuistWeb.Noora.Breadcrumbs
  import TuistWeb.Noora.Sidebar
  import TuistWeb.Noora.Icon
  import TuistWeb.Noora.LineDivider

  defdelegate noora_button(assigns), to: TuistWeb.Noora.Button, as: :button

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
        {@selected_account.name}
        <:content>
          <a :for={account <- @current_user_accounts} href={~p"/#{account.name}/projects"}>
            {account.name}
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
            <p class="text-md semibold">{gettext("Projects")}</p>
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
              <p class="text-md semibold">{gettext("Billing")}</p>
            </a>
          </li>
        <% end %>
      </ul>
    </nav>
    """
  end

  def project_sidebar(assigns) do
    ~H"""
    <%= if FunWithFlags.enabled?(:noora) do %>
      <.noora_project_sidebar {assigns} />
    <% else %>
      <.legacy_project_sidebar {assigns} />
    <% end %>
    """
  end

  attr :selected_project, :map, required: true
  attr :selected_account, :map, required: true
  attr :current_path, :string, required: true

  defp noora_project_sidebar(assigns) do
    ~H"""
    <.sidebar>
      <% overview_path = ~p"/noora/#{@selected_account.name}/#{@selected_project.name}" %>
      <.sidebar_item
        label="Overview"
        icon="smart_home"
        navigate={overview_path}
        selected={overview_path == @current_path}
      />
      <% test_runs_path = ~p"/#{@selected_account.name}/#{@selected_project.name}/test_runs"
      tests_default_open = @current_path in [test_runs_path] %>
      <.sidebar_item
        label="Test runs"
        icon="dashboard"
        navigate={test_runs_path}
        selected={test_runs_path == @current_path}
      />
      <.sidebar_group id="binary_cache" label="Binary cache" icon="database">
        <.sidebar_item label="Cache runs" icon="schema" />
      </.sidebar_group>
      <% previews_path = ~p"/noora/#{@selected_account.name}/#{@selected_project.name}/previews" %>
      <.sidebar_item
        label="Previews"
        icon="devices"
        navigate={previews_path}
        selected={previews_path == @current_path}
      />
    </.sidebar>
    """
  end

  attr :selected_project, :map, required: true
  attr :selected_account, :map, required: true
  attr :current_user, :map, required: true
  attr :current_path, :string, required: true

  defp legacy_project_sidebar(assigns) do
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
                <p class="text-md semibold">{gettext("Dashboard")}</p>
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
              <p class="text-md semibold">{gettext("Runs")}</p>
            </.link>
          </li>

          <%!-- Temporarily disabled due to performance issues --%>
          <%!-- <% tests_path = ~p"/#{@selected_account.name}/#{@selected_project.name}/tests" %>
          <li
            class="sidebar__navigation-list__item"
            aria-selected={if tests_path == @current_path, do: "true", else: "false"}
            aria-current={if tests_path == @current_path, do: "page", else: nil}
          >
            <.link patch={tests_path}>
              <.check_circle_icon />
              <p class="text-md semibold"><%= gettext("Tests") %></p>
            </.link>
          </li> --%>

          <% previews_path = ~p"/#{@selected_account.name}/#{@selected_project.name}/previews" %>
          <li
            class="sidebar__navigation-list__item"
            aria-selected={if previews_path == @current_path, do: "true", else: "false"}
            aria-current={if previews_path == @current_path, do: "page", else: nil}
          >
            <.link patch={previews_path}>
              <.phone_icon />
              <p class="text-md semibold">{gettext("Previews")}</p>
            </.link>
          </li>
        </ul>
        <%= if is_nil(@current_user) do %>
          <.link href={~p"/users/log_in"}>
            <.legacy_button variant="primary" class="sidebar__sign-in-button">
              {gettext("Sign in")}
            </.legacy_button>
          </.link>
        <% end %>
      </nav>
    <% end %>
    """
  end

  attr :breadcrumbs, :list, required: true
  attr :current_user, :map, required: true
  attr :selected_account, :map, required: true
  attr :latest_cli_release, :map, required: true
  attr :latest_app_release, :map, required: true

  def headerbar(assigns) do
    if FunWithFlags.enabled?(:noora) do
      ~H"""
      <header class="headerbar">
        <div data-part="left-section">
          <.link navigate={~p"/#{@selected_account.name}/projects"}>
            <img src="/images/tuist_dashboard.png" alt={gettext("Tuist Icon")} class="headerbar__logo" />
          </.link>
          <.headerbar_breadcrumbs breadcrumbs={@breadcrumbs} />
        </div>
        <div data-part="right-section">
          <.link href={Tuist.Environment.get_url(:documentation)} target="_blank">
            <.button variant="secondary" icon_only>
              <.book />
            </.button>
          </.link>
          <%= if not is_nil(@current_user) do %>
            <.account_dropdown latest_app_release={@latest_app_release} current_user={@current_user} />
          <% end %>
        </div>
      </header>
      <.line_divider />
      """
    else
      ~H"""
      <header class="headerbar">
        <.link navigate={~p"/#{@selected_account.name}/projects"}>
          <img
            src="/images/tuist_logo_32x32@2x.png"
            alt={gettext("Tuist Icon")}
            class="headerbar__logo"
          />
        </.link>
        <.headerbar_breadcrumbs breadcrumbs={@breadcrumbs} />
        <nav class="headerbar__links">
          <a
            :if={latest_cli_release = @latest_cli_release.ok? && @latest_cli_release.result}
            class="headerbar__links__release-badge"
            target="_blank"
            href={latest_cli_release.html_url}
          >
            <.legacy_badge
              title={"#{gettext("New release:")} #{latest_cli_release.name}"}
              kind={:brand}
            />
          </a>
          <a class="headerbar__links__link text--small" href="https://docs.tuist.io" target="_blank">
            <.book_open_icon class="headerbar__links__icon" />
            {gettext("Documentation")}
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
                  {@current_user.email}
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
  end

  attr :breadcrumbs, :list, required: true

  def headerbar_breadcrumbs(assigns) do
    if FunWithFlags.enabled?(:noora) do
      ~H"""
      <.breadcrumbs>
        <%= for {breadcrumb, index} <- Enum.with_index(@breadcrumbs) do %>
          <.breadcrumb
            id={"app-breadcrumb-#{index}"}
            label={breadcrumb.label}
            show_avatar={Map.get(breadcrumb, :show_avatar, false)}
            avatar_color={Map.get(breadcrumb, :avatar_color)}
          >
            <:icon :if={Map.get(breadcrumb, :icon)}><.icon name={Map.get(breadcrumb, :icon)} /></:icon>
            <.breadcrumb_item
              :for={breadcrumb_item <- breadcrumb.items}
              value={breadcrumb_item.value}
              label={breadcrumb_item.label}
              selected={breadcrumb_item.selected}
              href={breadcrumb_item.href}
              show_avatar={Map.get(breadcrumb_item, :show_avatar, false)}
              avatar_color={Map.get(breadcrumb_item, :avatar_color)}
            />
          </.breadcrumb>
        <% end %>
      </.breadcrumbs>
      """
    else
      ~H"""
      <nav :if={not Enum.empty?(@breadcrumbs)} class="headerbar__breadcrumbs">
        <ol class="headerbar__breadcrumbs__list">
          <%= for {breadcrumb, index} <- Enum.with_index(@breadcrumbs) do %>
            <%= cond do %>
              <% Map.get(breadcrumb, :href) -> %>
                <a href={breadcrumb.href} class="headerbar__breadcrumbs__list-link-item">
                  {Phoenix.HTML.raw(breadcrumb.label)}
                </a>
              <% Enum.empty?(Map.get(breadcrumb, :items, []))-> %>
                <span class="headerbar__breadcrumbs__text-item">
                  {Phoenix.HTML.raw(breadcrumb.label)}
                </span>
              <% true -> %>
                <.headless_dropdown dropdown_id={"breadcrumbs-item-#{index}-#{breadcrumb.label}"}>
                  <:activator :let={attrs}>
                    <div class="headerbar__breadcrumbs__dropdown-item" {attrs}>
                      {Phoenix.HTML.raw(breadcrumb.label)}
                      <.chevron_selector_horizontal class="headerbar__breadcrumbs__dropdown-item__icon" />
                    </div>
                  </:activator>
                  <div class="headerbar__breadcrumbs__dropdown-item__menu">
                    <a
                      :for={%{label: item_content, href: item_href} <- breadcrumb.items}
                      class="headerbar__breadcrumbs__dropdown-item__menu__item"
                      href={item_href}
                    >
                      {item_content}
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
