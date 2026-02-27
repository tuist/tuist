defmodule TuistWeb.TestCaseRunLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyTabStateBackground
  import TuistWeb.Helpers.FailureMessage
  import TuistWeb.Helpers.StackFrames
  import TuistWeb.Helpers.TestLabels
  import TuistWeb.Helpers.VCSLinks
  import TuistWeb.Runs.RanByBadge

  alias Tuist.Projects
  alias Tuist.Tests
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def mount(params, _session, %{assigns: %{selected_project: project}} = socket) do
    test_case_run =
      case Tests.get_test_case_run_by_id(params["test_case_run_id"],
             preload: [:failures, :repetitions, crash_report: :test_case_run_attachment]
           ) do
        {:ok, run} ->
          Tuist.Repo.preload(run, :ran_by_account)

        {:error, :not_found} ->
          raise NotFoundError, dgettext("dashboard_tests", "Test case run not found.")
      end

    if test_case_run.project_id != project.id do
      raise NotFoundError, dgettext("dashboard_tests", "Test case run not found.")
    end

    project = Tuist.Repo.preload(project, :vcs_connection)

    slug = Projects.get_project_slug_from_id(project.id)

    test_run =
      case Tests.get_test(test_case_run.test_run_id) do
        {:ok, run} -> run
        {:error, :not_found} -> nil
      end

    test_case =
      if test_case_run.test_case_id do
        case Tests.get_test_case_by_id(test_case_run.test_case_id) do
          {:ok, tc} -> tc
          {:error, :not_found} -> nil
        end
      end

    flaky_run_group =
      if test_case_run.is_flaky and test_case_run.test_case_id do
        Tests.get_flaky_run_group_for_test_case_run(test_case_run)
      end

    socket =
      socket
      |> assign(:selected_project, project)
      |> assign(:test_case_run, test_case_run)
      |> assign(:test_run, test_run)
      |> assign(:test_case, test_case)
      |> assign(:flaky_run_group, flaky_run_group)
      |> assign(:head_title, "#{test_case_run.name} · #{slug} · Tuist")

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    uri = URI.new!("?" <> URI.encode_query(params))
    selected_tab = params["tab"] || "overview"

    socket =
      socket
      |> assign(:selected_tab, selected_tab)
      |> assign(:uri, uri)

    {:noreply, socket}
  end
end
