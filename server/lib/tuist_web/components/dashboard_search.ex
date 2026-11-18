defmodule TuistWeb.Components.DashboardSearch do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  def trigger(assigns) do
    ~H"""
    <button
      type="button"
      class="dashboard-search-trigger"
      phx-click={Phoenix.LiveView.JS.dispatch("dashboard-search:open")}
      aria-label={dgettext("dashboard", "Search Tuist")}
      aria-haspopup="dialog"
      aria-controls="dashboard-search-dialog"
    >
      <.search />
      <span>{dgettext("dashboard", "Search")}</span>
      <kbd data-search-shortcut>⌘ K</kbd>
    </button>
    """
  end

  attr :account, :map, required: true
  attr :project, :map, default: nil
  attr :user, :map, required: true

  def palette(assigns) do
    ~H"""
    <div
      id="dashboard-search"
      phx-hook="DashboardSearch"
      data-endpoint={~p"/api/dashboard-search/#{@account.name}"}
      data-project={@project && @project.name}
      data-recent-key={"tuist:dashboard-project:#{@user.id}:#{@account.id}"}
      data-documentation={Tuist.Environment.get_url(:documentation)}
      data-pages={JSON.encode!(TuistWeb.DashboardNavigation.pages(@user, @account, @project))}
      data-filters={
        JSON.encode!([
          %{key: "is", example: "is:test-run", description: dgettext("dashboard", "Type of result")},
          %{
            key: "project",
            example: "project:ios-app",
            description: dgettext("dashboard", "Project name")
          },
          %{key: "branch", example: "branch:main", description: dgettext("dashboard", "Git branch")},
          %{
            key: "commit",
            example: "commit:abc1234",
            description: dgettext("dashboard", "Commit SHA or prefix")
          },
          %{
            key: "status",
            example: "status:failed",
            description: dgettext("dashboard", "Run outcome")
          },
          %{
            key: "date",
            example: "date:yesterday",
            description: dgettext("dashboard", "Date or range (UTC)")
          },
          %{
            key: "pr",
            example: "pr:123",
            description: dgettext("dashboard", "Pull request number, when recorded")
          }
        ])
      }
      data-labels={
        JSON.encode!(%{
          page: dgettext("dashboard", "Pages"),
          recent: dgettext("dashboard", "Recent"),
          project: dgettext("dashboard", "Projects"),
          test_case: dgettext("dashboard", "Test Cases"),
          build: dgettext("dashboard", "Build Runs"),
          test_run: dgettext("dashboard", "Test Runs"),
          preview: dgettext("dashboard", "Previews"),
          help: dgettext("dashboard", "Help"),
          filter: dgettext("dashboard", "Suggested filters"),
          open_in: dgettext("dashboard", "Open %{page} in…", page: "%{page}"),
          picker_placeholder: dgettext("dashboard", "Find a project…"),
          picker_back: dgettext("dashboard", "Back to search"),
          window: dgettext("dashboard", "Run lookup covers the last 30 days. Dates use UTC."),
          loading: dgettext("dashboard", "Searching…"),
          empty: dgettext("dashboard", "No results."),
          empty_title: dgettext("dashboard", "No results for “%{query}”", query: "%{query}"),
          throttled:
            dgettext(
              "dashboard",
              "Search is busy. Try again shortly. You can still navigate to pages."
            ),
          unavailable:
            dgettext("dashboard", "Some results are unavailable. You can still navigate to pages."),
          documentation: dgettext("dashboard", "Documentation")
        })
      }
    >
      <template data-project-badge>
        <.badge label="" color="neutral" style="light-fill">
          <:icon><.folders /></:icon>
        </.badge>
      </template>
      <template data-icon="page"><.external_link /></template>
      <template
        :for={
          icon <-
            ~w(smart_home versions chart_column subtask dashboard exchange progress_x lock stack_2 umbrella filter database schema filters apps devices package settings server folders users credit_card webhook category box_model_2 chart_arcs file_text list_tree alert_circle)
        }
        data-icon={icon}
      >
        <.icon name={icon} />
      </template>
      <template data-icon="project"><.folders /></template>
      <template data-icon="test_case"><.subtask /></template>
      <template data-icon="build"><.versions /></template>
      <template data-icon="test_run"><.dashboard /></template>
      <template data-icon="preview"><.devices /></template>
      <template data-icon="help"><.book /></template>
      <template data-icon="filter"><.filter /></template>
      <%!-- Tabler corner-down-left, which Noora does not ship. --%>
      <template data-enter-icon>
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <path d="M18 6v6a3 3 0 0 1 -3 3h-10l4 -4m0 8l-4 -4" />
        </svg>
      </template>
      <dialog
        id="dashboard-search-dialog"
        aria-label={dgettext("dashboard", "Search Tuist")}
        phx-update="ignore"
      >
        <div data-part="picker-heading" hidden>
          <button type="button" data-back><.arrow_left /></button>
          <span></span>
        </div>
        <div data-part="search-row">
          <.search />
          <input
            id="dashboard-search-input"
            type="search"
            role="combobox"
            aria-expanded="true"
            aria-autocomplete="list"
            aria-controls="dashboard-search-results"
            aria-label={dgettext("dashboard", "Search Tuist")}
            placeholder={
              if @project,
                do: dgettext("dashboard", "Search in %{project}…", project: @project.name),
                else: dgettext("dashboard", "Search projects, tests, runs, and pages…")
            }
            autocomplete="off"
            maxlength="160"
          />
          <button type="button" data-close aria-label={dgettext("dashboard", "Close search")}>
            <.close />
          </button>
        </div>
        <p data-part="search-validation" role="alert" hidden></p>
        <p data-part="search-status" role="status" aria-live="polite"></p>
        <div
          id="dashboard-search-results"
          role="listbox"
          aria-label={dgettext("dashboard", "Search results")}
        >
        </div>
        <div data-part="search-empty" aria-hidden="true" hidden>
          <.table_empty_state
            icon="search"
            title={dgettext("dashboard", "No results")}
            subtitle={
              dgettext(
                "dashboard",
                "Builds and test runs appear when you search by ID or link, or with a filter like is:test-run."
              )
            }
          />
        </div>
        <div data-part="search-error" hidden>
          <span role="status" aria-live="polite"></span>
          <button type="button" data-retry>{dgettext("dashboard", "Retry")}</button>
        </div>
        <footer>
          <span><kbd>↑</kbd><kbd>↓</kbd> {dgettext("dashboard", "Navigate")}</span>
          <span><kbd>esc</kbd> {dgettext("dashboard", "to close")}</span>
        </footer>
      </dialog>
    </div>
    """
  end
end
