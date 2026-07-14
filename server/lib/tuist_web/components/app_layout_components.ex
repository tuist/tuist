defmodule TuistWeb.AppLayoutComponents do
  @moduledoc ~S"""
  A collection of components that are used from the layouts.
  """
  use TuistWeb, :live_component
  use Noora

  import TuistWeb.AccountDropdown

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Projects.Project

  attr(:selected_project, :map, required: true)
  attr(:selected_account, :map, required: true)
  attr(:selected_run, :map, required: true)
  attr(:current_path, :string, required: true)
  attr(:current_user, :map, required: true)

  def project_sidebar(assigns) do
    ~H"""
    <.sidebar>
      <% overview_path = ~p"/#{@selected_account.name}/#{@selected_project.name}" %>
      <.sidebar_item
        label={dgettext("dashboard", "Overview")}
        icon="smart_home"
        navigate={overview_path}
        selected={overview_path == @current_path}
      />
      <.sidebar_group
        :if={Project.xcode_project?(@selected_project)}
        id="sidebar-builds"
        label={dgettext("dashboard", "Builds")}
        icon="versions"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/builds"}
        selected={@current_path == ~p"/#{@selected_account.name}/#{@selected_project.name}/builds"}
        default_open={
          String.starts_with?(
            @current_path,
            ~p"/#{@selected_account.name}/#{@selected_project.name}/builds"
          )
        }
        phx-update="ignore"
      >
        <.sidebar_item
          label={dgettext("dashboard", "Build Runs")}
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
      <.sidebar_group
        :if={Project.xcode_project?(@selected_project)}
        id="sidebar-tests"
        label={dgettext("dashboard", "Tests")}
        icon="subtask"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests"}
        selected={@current_path == ~p"/#{@selected_account.name}/#{@selected_project.name}/tests"}
        default_open={
          String.starts_with?(
            @current_path,
            ~p"/#{@selected_account.name}/#{@selected_project.name}/tests"
          )
        }
        phx-update="ignore"
      >
        <.sidebar_item
          label={dgettext("dashboard", "Test Runs")}
          icon="dashboard"
          navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests/test-runs"}
          selected={
            String.starts_with?(
              @current_path,
              ~p"/#{@selected_account.name}/#{@selected_project.name}/tests/test-runs"
            ) or
              String.starts_with?(
                @current_path,
                "/#{@selected_account.name}/#{@selected_project.name}/tests/test-cases/runs"
              )
          }
        />
        <.sidebar_item
          label={dgettext("dashboard", "Test Cases")}
          icon="exchange"
          navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests/test-cases"}
          selected={
            String.starts_with?(
              @current_path,
              ~p"/#{@selected_account.name}/#{@selected_project.name}/tests/test-cases"
            ) and
              not String.starts_with?(
                @current_path,
                "/#{@selected_account.name}/#{@selected_project.name}/tests/test-cases/runs"
              )
          }
        />
        <.sidebar_item
          label={dgettext("dashboard", "Flaky Tests")}
          icon="progress_x"
          navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests/flaky-tests"}
          selected={
            String.starts_with?(
              @current_path,
              ~p"/#{@selected_account.name}/#{@selected_project.name}/tests/flaky-tests"
            )
          }
        />
        <.sidebar_item
          label={dgettext("dashboard", "Quarantined Tests")}
          icon="lock"
          navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests/quarantined-tests"}
          selected={
            String.starts_with?(
              @current_path,
              ~p"/#{@selected_account.name}/#{@selected_project.name}/tests/quarantined-tests"
            )
          }
        />
        <.sidebar_item
          label={dgettext("dashboard", "Shards")}
          icon="stack_2"
          navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests/shards"}
          selected={
            String.starts_with?(
              @current_path,
              ~p"/#{@selected_account.name}/#{@selected_project.name}/tests/shards"
            )
          }
        />
      </.sidebar_group>
      <.sidebar_group
        :if={Project.xcode_project?(@selected_project)}
        id="sidebar-module-cache"
        label={dgettext("dashboard", "Module Cache")}
        icon="database"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/module-cache"}
        selected={
          @current_path == ~p"/#{@selected_account.name}/#{@selected_project.name}/module-cache"
        }
        default_open={
          String.starts_with?(
            @current_path,
            ~p"/#{@selected_account.name}/#{@selected_project.name}/module-cache"
          ) or
            (not is_nil(@selected_run) and
               (@selected_run.name == "generate" or @selected_run.name == "cache"))
        }
        phx-update="ignore"
      >
        <.sidebar_item
          label={dgettext("dashboard", "Cache Runs")}
          icon="schema"
          navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/module-cache/cache-runs"}
          selected={
            String.starts_with?(
              @current_path,
              ~p"/#{@selected_account.name}/#{@selected_project.name}/module-cache/cache-runs"
            ) or
              (not is_nil(@selected_run) and @selected_run.name == "cache")
          }
        />
        <.sidebar_item
          label={dgettext("dashboard", "Generations")}
          icon="filters"
          navigate={
            ~p"/#{@selected_account.name}/#{@selected_project.name}/module-cache/generate-runs"
          }
          selected={
            String.starts_with?(
              @current_path,
              ~p"/#{@selected_account.name}/#{@selected_project.name}/module-cache/generate-runs"
            ) or
              (not is_nil(@selected_run) and @selected_run.name == "generate")
          }
        />
      </.sidebar_group>
      <.sidebar_item
        :if={Project.xcode_project?(@selected_project)}
        label={dgettext("dashboard", "Xcode Cache")}
        icon="server"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/xcode-cache"}
        selected={
          ~p"/#{@selected_account.name}/#{@selected_project.name}/xcode-cache" == @current_path
        }
      />
      <.sidebar_group
        :if={Project.gradle_project?(@selected_project)}
        id="sidebar-gradle-builds"
        label={dgettext("dashboard", "Builds")}
        icon="versions"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/builds"}
        selected={@current_path == ~p"/#{@selected_account.name}/#{@selected_project.name}/builds"}
        default_open={
          String.starts_with?(
            @current_path,
            ~p"/#{@selected_account.name}/#{@selected_project.name}/builds"
          )
        }
        phx-update="ignore"
      >
        <.sidebar_item
          label={dgettext("dashboard", "Build Runs")}
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
      <.sidebar_group
        :if={Project.gradle_project?(@selected_project)}
        id="sidebar-gradle-tests"
        label={dgettext("dashboard", "Tests")}
        icon="subtask"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests"}
        selected={@current_path == ~p"/#{@selected_account.name}/#{@selected_project.name}/tests"}
        default_open={
          String.starts_with?(
            @current_path,
            ~p"/#{@selected_account.name}/#{@selected_project.name}/tests"
          )
        }
        phx-update="ignore"
      >
        <.sidebar_item
          label={dgettext("dashboard", "Test Runs")}
          icon="dashboard"
          navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests/test-runs"}
          selected={
            String.starts_with?(
              @current_path,
              ~p"/#{@selected_account.name}/#{@selected_project.name}/tests/test-runs"
            ) or
              String.starts_with?(
                @current_path,
                "/#{@selected_account.name}/#{@selected_project.name}/tests/test-cases/runs"
              )
          }
        />
        <.sidebar_item
          label={dgettext("dashboard", "Test Cases")}
          icon="exchange"
          navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests/test-cases"}
          selected={
            String.starts_with?(
              @current_path,
              ~p"/#{@selected_account.name}/#{@selected_project.name}/tests/test-cases"
            ) and
              not String.starts_with?(
                @current_path,
                "/#{@selected_account.name}/#{@selected_project.name}/tests/test-cases/runs"
              )
          }
        />
        <.sidebar_item
          label={dgettext("dashboard", "Flaky Tests")}
          icon="progress_x"
          navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests/flaky-tests"}
          selected={
            String.starts_with?(
              @current_path,
              ~p"/#{@selected_account.name}/#{@selected_project.name}/tests/flaky-tests"
            )
          }
        />
        <.sidebar_item
          label={dgettext("dashboard", "Quarantined Tests")}
          icon="lock"
          navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests/quarantined-tests"}
          selected={
            String.starts_with?(
              @current_path,
              ~p"/#{@selected_account.name}/#{@selected_project.name}/tests/quarantined-tests"
            )
          }
        />
        <.sidebar_item
          label={dgettext("dashboard", "Shards")}
          icon="stack_2"
          navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/tests/shards"}
          selected={
            String.starts_with?(
              @current_path,
              ~p"/#{@selected_account.name}/#{@selected_project.name}/tests/shards"
            )
          }
        />
      </.sidebar_group>
      <.sidebar_item
        :if={Project.gradle_project?(@selected_project)}
        label={dgettext("dashboard", "Gradle Cache")}
        icon="server"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/gradle-cache"}
        selected={
          String.starts_with?(
            @current_path,
            ~p"/#{@selected_account.name}/#{@selected_project.name}/gradle-cache"
          )
        }
      />
      <.sidebar_item
        label={dgettext("dashboard", "Previews")}
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
        label={dgettext("dashboard", "Bundles")}
        icon="chart_donut_4"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/bundles"}
        selected={
          String.starts_with?(
            @current_path,
            ~p"/#{@selected_account.name}/#{@selected_project.name}/bundles"
          )
        }
      />
      <.sidebar_item
        :if={Tuist.Authorization.authorize(:project_update, @current_user, @selected_project) == :ok}
        label={dgettext("dashboard", "Project Settings")}
        icon="settings"
        navigate={~p"/#{@selected_account.name}/#{@selected_project.name}/settings"}
        selected={
          String.starts_with?(
            @current_path,
            ~p"/#{@selected_account.name}/#{@selected_project.name}/settings"
          )
        }
      />
    </.sidebar>
    """
  end

  attr(:selected_account, :map, required: true)
  attr(:current_path, :string, required: true)
  attr(:current_user, :map, required: true)

  def account_sidebar(assigns) do
    ~H"""
    <.sidebar>
      <% projects_path = ~p"/#{@selected_account.name}/projects" %>
      <% runners_path = ~p"/#{@selected_account.name}/runners" %>
      <% runner_workflows_path = ~p"/#{@selected_account.name}/runners/workflows" %>
      <% runner_jobs_path = ~p"/#{@selected_account.name}/runners/jobs" %>
      <% runner_profiles_path = ~p"/#{@selected_account.name}/runners/profiles" %>
      <.sidebar_item
        label={dgettext("dashboard", "Projects")}
        icon="folders"
        navigate={projects_path}
        selected={
          @current_path == ~p"/#{@selected_account.name}" or
            String.starts_with?(@current_path, projects_path)
        }
      />
      <.sidebar_group
        :if={FeatureFlags.runners_enabled?(@selected_account)}
        id="sidebar-runners"
        label={dgettext("dashboard", "Runners")}
        icon="server"
        navigate={runners_path}
        selected={@current_path == runners_path}
        default_open={String.starts_with?(@current_path, runners_path)}
        phx-update="ignore"
      >
        <.sidebar_item
          label={dgettext("dashboard", "Workflows")}
          icon="versions"
          navigate={runner_workflows_path}
          selected={String.starts_with?(@current_path, runner_workflows_path)}
        />
        <.sidebar_item
          label={dgettext("dashboard", "Jobs")}
          icon="stack_2"
          navigate={runner_jobs_path}
          selected={String.starts_with?(@current_path, runner_jobs_path)}
        />
        <.sidebar_item
          label={dgettext("dashboard", "Profiles")}
          icon="category"
          navigate={runner_profiles_path}
          selected={String.starts_with?(@current_path, runner_profiles_path)}
        />
      </.sidebar_group>
      <.sidebar_item
        :if={Accounts.organization?(@selected_account)}
        label={dgettext("dashboard", "Members")}
        icon="users"
        navigate={~p"/#{@selected_account.name}/members"}
        selected={String.starts_with?(@current_path, ~p"/#{@selected_account.name}/members")}
      />
      <.sidebar_item
        :if={Authorization.authorize(:account_update, @current_user, @selected_account) == :ok}
        label={dgettext("dashboard", "Webhooks")}
        icon="webhook"
        navigate={~p"/#{@selected_account.name}/webhooks"}
        selected={String.starts_with?(@current_path, ~p"/#{@selected_account.name}/webhooks")}
      />
      <.sidebar_item
        :if={
          FeatureFlags.kura_enabled?(@selected_account) and
            Authorization.authorize(:account_update, @current_user, @selected_account) == :ok
        }
        label={dgettext("dashboard", "Cache")}
        icon="database"
        navigate={~p"/#{@selected_account.name}/cache"}
        selected={String.starts_with?(@current_path, ~p"/#{@selected_account.name}/cache")}
      />
      <.sidebar_item
        :if={Authorization.authorize(:account_update, @current_user, @selected_account) == :ok}
        label={dgettext("dashboard", "Billing")}
        icon="credit_card"
        navigate={~p"/#{@selected_account.name}/billing"}
        selected={String.starts_with?(@current_path, ~p"/#{@selected_account.name}/billing")}
      />
      <.sidebar_item
        :if={FeatureFlags.kura_enabled?(@selected_account)}
        label={dgettext("dashboard", "Usage")}
        icon="chart_column"
        navigate={~p"/#{@selected_account.name}/usage"}
        selected={String.starts_with?(@current_path, ~p"/#{@selected_account.name}/usage")}
      />
      <.sidebar_item
        :if={Authorization.authorize(:account_update, @current_user, @selected_account) == :ok}
        label={dgettext("dashboard", "Settings")}
        icon="settings"
        navigate={~p"/#{@selected_account.name}/settings"}
        selected={String.starts_with?(@current_path, ~p"/#{@selected_account.name}/settings")}
      />
    </.sidebar>
    """
  end

  attr(:selected_account, :map, required: true)
  attr(:current_path, :string, required: true)
  attr(:current_user, :map, required: true)

  def settings_tab_menu(assigns) do
    ~H"""
    <.tab_menu_horizontal>
      <% general_path = ~p"/#{@selected_account.name}/settings" %>
      <% integrations_path = ~p"/#{@selected_account.name}/settings/integrations" %>
      <% authentication_path = ~p"/#{@selected_account.name}/settings/authentication" %>
      <.tab_menu_horizontal_item
        label={dgettext("dashboard", "General")}
        selected={@current_path == general_path}
        navigate={general_path}
      />
      <.tab_menu_horizontal_item
        :if={Authorization.authorize(:account_update, @current_user, @selected_account) == :ok}
        label={dgettext("dashboard", "Integrations")}
        selected={String.starts_with?(@current_path, integrations_path)}
        navigate={integrations_path}
      />
      <.tab_menu_horizontal_item
        :if={
          Accounts.organization?(@selected_account) and
            Authorization.authorize(:account_update, @current_user, @selected_account) == :ok
        }
        label={dgettext("dashboard", "Authentication")}
        selected={String.starts_with?(@current_path, authentication_path)}
        navigate={authentication_path}
      />
    </.tab_menu_horizontal>
    """
  end

  attr(:current_path, :string, required: true)

  def ops_sidebar(assigns) do
    ~H"""
    <.sidebar>
      <.sidebar_item
        label={dgettext("dashboard", "Cache")}
        icon="server"
        navigate={~p"/ops"}
        selected={@current_path == "/ops"}
      />
      <.sidebar_item
        :if={Tuist.Environment.tuist_hosted?()}
        label={dgettext("dashboard", "Accounts")}
        icon="users"
        navigate={~p"/ops/accounts"}
        selected={String.starts_with?(@current_path, "/ops/accounts")}
      />
      <.sidebar_item
        label={dgettext("dashboard", "Database")}
        icon="database"
        navigate={~p"/ops/db"}
        selected={String.starts_with?(@current_path, "/ops/db")}
      />
      <.sidebar_item
        label={dgettext("dashboard", "LiveDashboard")}
        icon="dashboard"
        navigate={~p"/ops/dashboard"}
        selected={String.starts_with?(@current_path, "/ops/dashboard")}
      />
      <.sidebar_item
        label={dgettext("dashboard", "Jobs")}
        icon="stack_2"
        navigate={~p"/ops/oban"}
        selected={String.starts_with?(@current_path, "/ops/oban")}
      />
      <.sidebar_item
        label={dgettext("dashboard", "Flags")}
        icon="filter"
        navigate={~p"/ops/flags"}
        selected={String.starts_with?(@current_path, "/ops/flags")}
      />
      <.sidebar_item
        :if={Tuist.Environment.dev?()}
        label={dgettext("dashboard", "Emails")}
        icon="mail"
        navigate={~p"/ops/sent_emails"}
        selected={String.starts_with?(@current_path, "/ops/sent_emails")}
      />
      <.sidebar_item
        :if={Tuist.Environment.dev?() and not Tuist.Environment.dev_use_remote_storage?()}
        label={dgettext("dashboard", "Storage")}
        icon="database"
        href={"http://localhost:#{Tuist.Environment.minio_console_port()}"}
        target="_blank"
        rel="noopener noreferrer"
        external
      />
      <.sidebar_item
        label={dgettext("dashboard", "Errors")}
        icon="alert_triangle"
        href="https://sentry.io/organizations/tuist/issues/"
        target="_blank"
        rel="noopener noreferrer"
        external
      />
      <.sidebar_item
        label={dgettext("dashboard", "Grafana")}
        icon="chart_column"
        href="https://tuist.grafana.net"
        target="_blank"
        rel="noopener noreferrer"
        external
      />
    </.sidebar>
    """
  end

  attr(:breadcrumbs, :list, required: true)
  attr(:current_user, :map, required: true)
  attr(:selected_account, :map, required: true)
  attr(:latest_app_release, :map, required: true)
  attr(:title, :string, default: nil)

  def headerbar(assigns) do
    ~H"""
    <header class="headerbar">
      <div data-part="left-section">
        <.link navigate={~p"/#{@selected_account.name}/projects"}>
          <img
            src={~p"/images/tuist_dashboard.png"}
            alt={dgettext("dashboard", "Tuist Icon")}
            class="headerbar__logo"
            decoding="async"
          />
        </.link>
        <span :if={@title} data-part="title">{@title}</span>
        <.headerbar_breadcrumbs breadcrumbs={@breadcrumbs} id="headerbar-breadcrumbs" />
      </div>
      <div data-part="right-section">
        <.badge
          :if={Tuist.Environment.server_version_identifier()}
          label={Tuist.Environment.server_version_identifier()}
          color="attention"
          style="light-fill"
          size="large"
        >
          <:icon><.git_branch /></:icon>
        </.badge>
        <.button
          variant="secondary"
          icon_only
          href={Tuist.Environment.get_url(:documentation)}
          target="_blank"
          rel="noopener noreferrer"
          aria-label={dgettext("dashboard", "Documentation")}
        >
          <.book />
        </.button>
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
              src={~p"/images/tuist_dashboard.png"}
              alt={dgettext("dashboard", "Tuist Icon")}
              class="headerbar__logo"
              decoding="async"
            />
          </.link>
          <span :if={@title} data-part="title">{@title}</span>
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
          href={
            Map.get(breadcrumb, :href) || (Enum.find(breadcrumb.items, & &1.selected) || %{})[:href]
          }
          show_avatar={Map.get(breadcrumb, :show_avatar, false)}
          avatar_color={Map.get(breadcrumb, :avatar_color)}
          badge_label={breadcrumb[:badge] && breadcrumb.badge.label}
          badge_color={breadcrumb[:badge] && breadcrumb.badge.color}
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
            icon={Map.get(breadcrumb_item, :icon)}
            badge_label={breadcrumb_item[:badge] && breadcrumb_item.badge.label}
            badge_color={breadcrumb_item[:badge] && breadcrumb_item.badge.color}
          />
          <:footer :if={Map.get(breadcrumb, :footer_items)}>
            <.breadcrumb_item
              :for={breadcrumb_item <- breadcrumb.footer_items}
              id={"#{@id}-#{breadcrumb_item.value}"}
              value={breadcrumb_item.value}
              label={breadcrumb_item.label}
              selected={breadcrumb_item.selected}
              href={breadcrumb_item.href}
              show_avatar={Map.get(breadcrumb_item, :show_avatar, false)}
              avatar_color={Map.get(breadcrumb_item, :avatar_color)}
              icon={Map.get(breadcrumb_item, :icon)}
              badge_label={breadcrumb_item[:badge] && breadcrumb_item.badge.label}
              badge_color={breadcrumb_item[:badge] && breadcrumb_item.badge.color}
            />
          </:footer>
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
