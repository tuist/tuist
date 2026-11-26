defmodule TuistWeb.TestRunTestCaseLive do
  @moduledoc """
  A test of a test run's coverage selection that has no test case run in it,
  such as one the selection skipped: its Selective Testing tab, scoped to the
  test run, which a test case run's page would show had it run. A test that
  did run goes to its test case run's page instead.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Helpers.TestLabels
  import TuistWeb.TestSelection.Components, only: [decision_label: 1]

  alias Tuist.Projects
  alias Tuist.Tests
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.TestSelection.TestCaseRunTab
  alias TuistWeb.Utilities.Query

  def mount(%{"test_run_id" => test_run_id, "test_case_id" => test_case_id}, _session, socket) do
    project = socket.assigns.selected_project

    with {:ok, %{project_id: project_id} = test_run} when project_id == project.id <- Tests.get_test(test_run_id),
         %{test: test} = selection <- TestCaseRunTab.load(project, test_run, %{test_case_id: test_case_id}) do
      if test.test_case_run_id do
        {:ok,
         redirect(socket,
           to:
             ~p"/#{project.account.name}/#{project.name}/tests/test-cases/runs/#{test.test_case_run_id}?tab=selective-testing"
         )}
      else
        slug = Projects.get_project_slug_from_id(project.id)

        {:ok,
         socket
         |> assign(:test_run, test_run)
         |> assign(:selection, selection)
         |> assign(:head_title, "#{test.name} · #{slug} · Tuist")}
      end
    else
      _ -> raise NotFoundError, dgettext("dashboard_tests", "Test case not found.")
    end
  end

  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)

    {:noreply,
     socket
     |> assign(:uri, URI.new!("?" <> URI.encode_query(params)))
     |> TestCaseRunTab.assign_files(socket.assigns.selection, params)}
  end

  def handle_event("search-selection-files", %{"search" => search}, socket) do
    {:noreply,
     push_patch(socket,
       to: socket.assigns.current_path <> "?" <> TestCaseRunTab.search_query(socket.assigns.uri, search),
       replace: true
     )}
  end

  def render(assigns) do
    assigns = assign(assigns, :test, assigns.selection.test)

    ~H"""
    <div id="test-case-run-detail">
      <.button
        label={
          if @test_run.scheme in [nil, ""] and
               @selected_project.build_system not in [:mix, :bazel, :cargo],
             do: dgettext("dashboard_tests", "Test Run"),
             else: test_run_label(@selected_project, @test_run.scheme)
        }
        data-part="back-button"
        variant="secondary"
        size="medium"
        navigate={
          ~p"/#{@selected_project.account.name}/#{@selected_project.name}/tests/test-runs/#{@test_run.id}?tab=test-optimizations"
        }
      >
        <:icon_left>
          <.icon name="arrow_left" />
        </:icon_left>
      </.button>

      <div data-part="header">
        <div data-part="title-group">
          <div data-part="title">
            <h1 data-part="label">{@test.name}</h1>
            <.badge
              label={decision_label(@test.decision)}
              color={if @test.decision == "selected", do: "primary", else: "neutral"}
              style="light-fill"
              size="medium"
            />
          </div>
          <.link_button
            navigate={
              ~p"/#{@selected_project.account.name}/#{@selected_project.name}/tests/test-cases/#{@test.test_case_id}"
            }
            label={dgettext("dashboard_tests", "Test Case: %{name}", name: @test.name)}
            size="large"
            underline
            data-part="test-case-link"
          >
            <:icon_left><.exchange /></:icon_left>
          </.link_button>
          <div :if={@test.module_name != "" or @test.suite_name != ""} data-part="badges">
            <.badge
              :if={@test.module_name != ""}
              label={"#{module_label(@selected_project)}: #{@test.module_name}"}
              color="primary"
              style="light-fill"
              size="medium"
            />
            <.badge
              :if={@test.suite_name != ""}
              label={"#{suite_label(@selected_project)}: #{@test.suite_name}"}
              color="primary"
              style="light-fill"
              size="medium"
            />
          </div>
        </div>
      </div>

      <.tab_menu_horizontal>
        <.tab_menu_horizontal_item
          label={dgettext("dashboard_tests", "Selective Testing")}
          selected={true}
          patch={"?#{@uri.query}"}
          replace={true}
        />
      </.tab_menu_horizontal>

      <TestCaseRunTab.test_selection
        selection={@selection}
        all_files={@selection_all_files}
        files={@selection_files}
        search={@selection_files_search}
        page={@selection_files_page}
        total_pages={@selection_files_total_pages}
        uri={@uri}
        project={@selected_project}
        account={@selected_account}
        test_run_id={@test_run.id}
      />
    </div>
    """
  end
end
