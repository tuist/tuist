defmodule TuistWeb.AppLayoutComponents do
  @moduledoc ~S"""
  A collection of components that are used from the layouts.
  """
  use TuistWeb, :live_component
  use Noora

  import TuistWeb.AccountDropdown

  attr(:selected_project, :map, required: true)
  attr(:selected_account, :map, required: true)
  attr(:selected_run, :map, required: true)
  attr(:current_path, :string, required: true)

  def project_sidebar(assigns) do
    ~H"""
    <.sidebar>
      <% overview_path = ~p"/#{@selected_account.name}/#{@selected_project.name}" %>
      <.sidebar_item
        label={gettext("Overview")}
        icon="smart_home"
        navigate={overview_path}
        selected={overview_path == @current_path}
      />
      <.sidebar_item
        label={gettext("Test Runs")}
        icon="dashboard"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests/test-runs"}
        selected={
          ~p"/#{@selected_account.name}/#{@selected_project.name}/tests/test-runs" == @current_path or
            (not is_nil(@selected_run) and not Enum.empty?(@selected_run.test_targets))
        }
      />
      <.sidebar_item
        label={gettext("Cache Runs")}
        icon="schema"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/binary-cache/cache-runs"}
        selected={
          ~p"/#{@selected_account.name}/#{@selected_project.name}/binary-cache/cache-runs" ==
            @current_path or
            (not is_nil(@selected_run) and @selected_run.name == "cache")
        }
      />
      <.sidebar_item
        label={gettext("Generate Runs")}
        icon="filters"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/binary-cache/generate-runs"}
        selected={
          ~p"/#{@selected_account.name}/#{@selected_project.name}/binary-cache/generate-runs" ==
            @current_path or
            (not is_nil(@selected_run) and @selected_run.name == "generate")
        }
      />
      <.sidebar_item
        label={gettext("Previews")}
        icon="devices"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/previews"}
        selected={
          String.starts_with?(
            @current_path,
            ~p"/#{@selected_account.name}/#{@selected_project.name}/previews"
          )
        }
      />
      <.sidebar_item
        label={gettext("Bundles")}
        icon="chart_donut_4"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/bundles"}
        selected={
          String.starts_with?(
            @current_path,
            ~p"/#{@selected_account.name}/#{@selected_project.name}/bundles"
          )
        }
      />
      <.sidebar_group
        id="sidebar-builds"
        label={gettext("Builds")}
        icon="versions"
        navigate={
          @current_path != ~p"/#{@selected_account.name}/#{@selected_project.name}/builds" &&
            ~p"/#{@selected_account.name}/#{@selected_project.name}/builds"
        }
        selected={@current_path == ~p"/#{@selected_account.name}/#{@selected_project.name}/builds"}
        disabled={@current_path != ~p"/#{@selected_account.name}/#{@selected_project.name}/builds"}
        default_open={
          String.starts_with?(
            @current_path,
            ~p"/#{@selected_account.name}/#{@selected_project.name}/builds"
          )
        }
      >
        <.sidebar_item
          label={gettext("Build Runs")}
          icon="chart_column"
          navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/builds/build-runs"}
          selected={
            String.starts_with?(
              @current_path,
              ~p"/#{@selected_account.name}/#{@selected_project.name}/builds/build-runs"
            )
          }
        />
      </.sidebar_group>
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
    Phoenix.Component.assign(
      socket,
      :breadcrumbs,
      Map.get(socket.assigns, :breadcrumbs, []) ++ [breadcrumb]
    )
  end
end
