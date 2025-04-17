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

  attr(:current_path, :string, required: true)
  attr(:current_user, :map, required: true)
  attr(:selected_account, :map, required: true)
  attr(:current_user_accounts, :list, required: true)
  attr(:can_read_billing, :boolean, required: true)

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
    <.noora_project_sidebar {assigns} />
    """
  end

  attr(:selected_project, :map, required: true)
  attr(:selected_account, :map, required: true)
  attr(:selected_run, :map, required: true)
  attr(:current_path, :string, required: true)

  defp noora_project_sidebar(assigns) do
    ~H"""
    <.sidebar>
      <% overview_path = ~p"/#{@selected_account.name}/#{@selected_project.name}" %>
      <.sidebar_item
        label="Overview"
        icon="smart_home"
        navigate={overview_path}
        selected={overview_path == @current_path}
      />
      <.sidebar_item
        label="Test Runs"
        icon="dashboard"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests/test-runs"}
        selected={
          ~p"/#{@selected_account.name}/#{@selected_project.name}/tests/test-runs" == @current_path or
            (not is_nil(@selected_run) and not Enum.empty?(@selected_run.test_targets))
        }
      />
      <.sidebar_item
        label="Cache Runs"
        icon="schema"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/binary-cache/cache-runs"}
        selected={
          ~p"/#{@selected_account.name}/#{@selected_project.name}/binary-cache/cache-runs" ==
            @current_path or
            (not is_nil(@selected_run) and @selected_run.name == "cache")
        }
      />
      <.sidebar_item
        label="Generate Runs"
        icon="filters"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/binary-cache/generate-runs"}
        selected={
          ~p"/#{@selected_account.name}/#{@selected_project.name}/binary-cache/generate-runs" ==
            @current_path or
            (not is_nil(@selected_run) and @selected_run.name == "generate")
        }
      />
      <.sidebar_item
        label="Previews"
        icon="devices"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/previews"}
        selected={
          String.starts_with?(
            @current_path,
            ~p"/#{@selected_account.name}/#{@selected_project.name}/previews"
          )
        }
      />
    </.sidebar>
    """
  end

  attr(:breadcrumbs, :list, required: true)
  attr(:current_user, :map, required: true)
  attr(:selected_account, :map, required: true)
  attr(:latest_cli_release, :map, required: true)
  attr(:latest_app_release, :map, required: true)

  def headerbar(assigns) do
    ~H"""
    <header class="headerbar">
      <div data-part="left-section">
        <.link navigate={~p"/#{@selected_account.name}/projects"}>
          <img src="/images/tuist_dashboard.png" alt={gettext("Tuist Icon")} class="headerbar__logo" />
        </.link>
        <.headerbar_breadcrumbs breadcrumbs={@breadcrumbs} id="headerbar-breadcrumbs" />
      </div>
      <div data-part="right-section">
        <.link href={Tuist.Environment.get_url(:documentation)} target="_blank">
          <.button variant="secondary" icon_only>
            <.book />
          </.button>
        </.link>
        <%= if not is_nil(@current_user) do %>
          <.account_dropdown
            id="account-dropdown"
            latest_app_release={@latest_app_release}
            current_user={@current_user}
          />
        <% end %>
      </div>
    </header>
    <header class="mobile-headerbar">
      <div data-part="first-row">
        <div data-part="left-section">
          <.link navigate={~p"/#{@selected_account.name}/projects"}>
            <img
              src="/images/tuist_dashboard.png"
              alt={gettext("Tuist Icon")}
              class="headerbar__logo"
            />
          </.link>
        </div>
        <div data-part="right-section">
          <%= if not is_nil(@current_user) do %>
            <.account_dropdown
              id="mobile-account-dropdown"
              avatar_size="xsmall"
              latest_app_release={@latest_app_release}
              current_user={@current_user}
            />
          <% end %>
        </div>
      </div>
      <.line_divider />
      <div data-part="second-row">
        <.headerbar_breadcrumbs breadcrumbs={@breadcrumbs} id="mobile-headerbar-breadcrumbs" />
      </div>
    </header>
    <.line_divider />
    """
  end

  attr(:id, :string, required: true)
  attr(:breadcrumbs, :list, required: true)

  def headerbar_breadcrumbs(assigns) do
    ~H"""
    <.breadcrumbs>
      <%= for {breadcrumb, index} <- Enum.with_index(@breadcrumbs) do %>
        <.breadcrumb
          id={"#{@id}-#{index}"}
          label={breadcrumb.label}
          show_avatar={Map.get(breadcrumb, :show_avatar, false)}
          avatar_color={Map.get(breadcrumb, :avatar_color)}
        >
          <:icon :if={Map.get(breadcrumb, :icon)}><.icon name={Map.get(breadcrumb, :icon)} /></:icon>
          <.breadcrumb_item
            :for={breadcrumb_item <- breadcrumb.items}
            id={"#{@id}-#{breadcrumb_item.value}"}
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
