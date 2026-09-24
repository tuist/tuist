defmodule TuistWeb.CoverageDetailLive do
  @moduledoc """
  A commit's coverage in detail: what its runs measured, pooled over the
  schemes that measured it. Overview holds the totals and where the commit
  is thinnest; Targets and Files list everything it measured; Test Runs the
  runs behind it. The project's Code Coverage page (`TuistWeb.CoverageLive`)
  is the glance at the default branch that sends readers here.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components
  import TuistWeb.Helpers.TestLabels

  alias Tuist.FeatureFlags
  alias Tuist.Tests.Coverage.Commits
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @tabs ~w(overview targets files runs)
  @page_size 20
  # How many rows the overview's files hold: a highlight, not a listing.
  @highlight_size 5

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    if !FeatureFlags.xcode_coverage_enabled?(account) do
      raise NotFoundError, dgettext("dashboard_tests", "Code coverage is not enabled for this account.")
    end

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_tests", "Code Coverage")} · #{account.name}/#{project.name} · Tuist")
      |> assign(OpenGraph.og_image_assigns("tests"))

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  def handle_params(params, uri, socket) do
    query = Query.query_params(uri)

    socket =
      socket
      |> assign(:uri, URI.new!("?" <> URI.encode_query(query)))
      |> assign(:current_params, query)
      |> assign_subject(params)

    # The static render resolves the commit, so a missing one is still a 404,
    # and leaves the rest to the connected one.
    if connected?(socket) do
      {:noreply, socket |> assign(:loading, false) |> assign_tab(query)}
    else
      {:noreply, socket |> assign(:loading, true) |> assign(:tab, tab(query["tab"]))}
    end
  end

  @doc false
  def file_href(%{selected_account: account, selected_project: project, subject: subject, tab: tab}, path) do
    coverage_file_href(account.name, project.name, path, %{commit: subject.sha, tab: tab})
  end

  def handle_info({:test_created, _test_run}, socket) do
    {:noreply,
     socket
     |> assign_subject(socket.assigns.params)
     |> assign_tab(socket.assigns.current_params)}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  defp assign_subject(socket, params) do
    sha = params["git_commit_sha"]
    project = socket.assigns.selected_project
    summary = Commits.summary(project.id, sha)

    if is_nil(summary) do
      raise NotFoundError, dgettext("dashboard_tests", "No run of commit %{sha} gathered coverage.", sha: sha || "")
    end

    socket
    |> assign(:params, params)
    |> assign(:subject, %{name: short_sha(sha), sha: sha})
    |> assign(:summary, Map.put(summary, :reported, Commits.reported_figure(summary)))
  end

  defp assign_tab(socket, query) do
    socket = assign(socket, :tab, tab(query["tab"]))

    case socket.assigns.tab do
      "overview" -> assign_overview(socket)
      "targets" -> assign_targets(socket)
      "files" -> assign_files(socket, query)
      "runs" -> assign_runs(socket)
    end
  end

  defp tab(value) when value in @tabs, do: value
  defp tab(_value), do: "overview"

  defp assign_overview(%{assigns: %{selected_project: project, subject: subject}} = socket) do
    {files, _count} = Commits.list_files(project.id, subject.sha, 1, @highlight_size)

    socket
    |> assign(:least_covered_files, Enum.map(files, &Map.put(&1, :id, "gap-" <> &1.path)))
    |> assign(:unmeasured_files, unmeasured_files(project, subject.sha, @highlight_size))
  end

  defp assign_targets(%{assigns: %{selected_project: project, subject: subject}} = socket) do
    targets = Commits.targets(project.id, subject.sha)
    assign(socket, :target_rows, Enum.map(targets, &Map.put(&1, :id, "target-" <> &1.name)))
  end

  defp assign_files(%{assigns: %{selected_project: project, subject: subject}} = socket, query) do
    page = Query.bounded_page(query["page"])
    {files, count} = Commits.list_files(project.id, subject.sha, page, @page_size)
    total_pages = max(1, ceil(count / @page_size))

    socket
    |> assign(:file_rows, Enum.map(files, &Map.put(&1, :id, &1.path)))
    |> assign(:files_meta, %{current_page: min(page, total_pages), total_pages: total_pages})
    |> assign_unmeasured_page(project, subject.sha, query)
  end

  # The two lists page apart, each under its own parameter, so turning one
  # leaves the other where it was.
  defp assign_unmeasured_page(%{assigns: %{summary: summary}} = socket, project, sha, query) do
    total_pages = max(1, ceil(summary.unmeasured_files_count / @page_size))
    page = min(Query.bounded_page(query["unmeasured-page"]), total_pages)

    socket
    |> assign(:unmeasured_files, unmeasured_files(project, sha, @page_size, (page - 1) * @page_size))
    |> assign(:unmeasured_meta, %{current_page: page, total_pages: total_pages})
  end

  defp assign_runs(%{assigns: %{selected_project: project, subject: subject}} = socket) do
    runs = Commits.runs(project.id, subject.sha)
    assign(socket, :run_rows, runs |> Enum.reverse() |> Enum.map(&Map.put(&1, :id, &1.test_run_id)))
  end

  defp unmeasured_files(project, sha, limit, offset \\ 0) do
    project
    |> Commits.unmeasured_files(sha, limit: limit, offset: offset)
    |> Enum.map(&%{id: "unmeasured-" <> &1, path: &1})
  end

  def tabs, do: @tabs

  def tab_label("overview"), do: dgettext("dashboard_tests", "Overview")
  def tab_label("targets"), do: dgettext("dashboard_tests", "Targets")
  def tab_label("files"), do: dgettext("dashboard_tests", "Files")
  def tab_label("runs"), do: dgettext("dashboard_tests", "Test Runs")
end
