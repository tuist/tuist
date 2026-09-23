defmodule TuistWeb.CoverageFileLive do
  @moduledoc """
  One file's coverage on a page of its own, read within what it was opened
  from: a commit (reached through a branch, a pull request or the commit's
  own page, which the page leads back to), or a single test run.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components

  alias Tuist.FeatureFlags
  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Coverage.Evidence
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  @detail_tabs ~w(overview commits targets files runs)

  def mount(params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    if !FeatureFlags.xcode_coverage_enabled?(account) do
      raise NotFoundError, dgettext("dashboard_tests", "Code coverage is not enabled for this account.")
    end

    path = params["path"] |> List.wrap() |> Enum.join("/")

    {:ok,
     socket
     |> assign(:path, path)
     |> assign(:head_title, "#{Path.basename(path)} · #{account.name}/#{project.name} · Tuist")}
  end

  def handle_params(params, uri, socket) do
    query = Query.query_params(uri)
    socket = socket |> assign(:file, nil) |> assign(:tests, nil) |> assign(:changed, nil)

    if connected?(socket),
      do: {:noreply, assign_file(socket, params, query)},
      else: {:noreply, assign_scope(socket, params, query)}
  end

  defp assign_file(socket, params, query) do
    socket = assign_scope(socket, params, query)
    project = socket.assigns.selected_project
    path = socket.assigns.path

    {file, tests, changed} =
      case socket.assigns.scope do
        %{test_run: run} ->
          file = Coverage.file_detail(project.id, run.id, path)
          tests = file && Evidence.summary(run) && Evidence.covering(run, path)
          {file, tests, nil}

        %{commit: sha} ->
          file = Commits.file_detail(project.id, sha, path)

          tests =
            file && Evidence.covering(%{project_id: project.id, test_run_ids: Commits.run_ids(project.id, sha)}, path)

          {file, tests, file && Comparison.changed_lines(project.id, sha, file)}
      end

    socket
    |> assign(:loading, false)
    |> assign(:file, file)
    |> assign(:tests, tests)
    |> assign(:changed, changed)
  end

  defp assign_scope(%{assigns: %{live_action: :test_run, selected_project: project}} = socket, params, _query) do
    run =
      case Tests.get_test(params["test_run_id"]) do
        {:ok, %{project_id: project_id} = run} when project_id == project.id -> run
        _ -> raise NotFoundError, dgettext("dashboard_tests", "Test run not found.")
      end

    socket
    |> assign(:loading, true)
    |> assign(:scope, %{test_run: run})
    |> assign(:back, %{
      label: dgettext("dashboard_tests", "Test run"),
      href: "/#{socket.assigns.selected_account.name}/#{project.name}/tests/test-runs/#{run.id}?tab=coverage"
    })
  end

  defp assign_scope(%{assigns: %{selected_project: project, selected_account: account}} = socket, _params, query) do
    sha = query["commit"]

    if sha in [nil, ""] or is_nil(Commits.summary(project.id, sha)) do
      raise NotFoundError, dgettext("dashboard_tests", "No run of commit %{sha} gathered coverage.", sha: sha || "")
    end

    socket
    |> assign(:loading, true)
    |> assign(:scope, %{commit: sha})
    |> assign(:back, back(account, project, sha, query))
  end

  defp back(account, project, sha, query) do
    base = "/#{account.name}/#{project.name}/tests/coverage"
    tab = if query["tab"] in @detail_tabs, do: [{"tab", query["tab"]}], else: []

    cond do
      query["pull-request"] not in [nil, ""] ->
        %{
          label: dgettext("dashboard_tests", "Pull request #%{number}", number: query["pull-request"]),
          href:
            "#{base}/pull-requests/#{encode_path(query["pull-request"])}?" <>
              URI.encode_query([{"commit", sha} | tab])
        }

      query["branch"] not in [nil, ""] ->
        %{
          label: dgettext("dashboard_tests", "Branch %{name}", name: query["branch"]),
          href:
            "#{base}/branches/#{encode_path(query["branch"])}?" <>
              URI.encode_query(tab)
        }

      true ->
        %{
          label: dgettext("dashboard_tests", "Commit %{name}", name: short_sha(sha)),
          href: "#{base}/commits/#{encode_path(sha)}?" <> URI.encode_query(tab)
        }
    end
  end

  @doc "What the page's badge says it is read at."
  def scope_label(%{test_run: run}), do: dgettext("dashboard_tests", "Test run %{scheme}", scheme: run.scheme || "")
  def scope_label(%{commit: sha}), do: short_sha(sha)
end
