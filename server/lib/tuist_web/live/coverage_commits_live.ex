defmodule TuistWeb.CoverageCommitsLive do
  @moduledoc """
  The project's recent coverage commits: every commit a run gathered coverage
  for, on any branch or pull request and whatever its status, the most
  recently run first (`History.recent_commits_page/2`), each opening its own
  page. The Code Coverage page (`TuistWeb.CoverageLive`) charts only a
  branch's complete commits, so this is where a run that isn't charted there
  can be found.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components

  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.History
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @page_size 20

  # A run's coverage joins its commit a few seconds after the run lands
  # (`Tuist.Tests.Coverage.Workers.CommitWorker`), so the page reloads once
  # after a burst of runs rather than once per run, before the fold.
  @reload_delay to_timeout(second: 15)

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    if !Coverage.supported?(project) do
      raise NotFoundError, dgettext("dashboard_tests", "Code coverage isn't available for this project's build system.")
    end

    socket =
      socket
      |> assign(
        :head_title,
        "#{dgettext("dashboard_tests", "Coverage Commits")} · #{account.name}/#{project.name} · Tuist"
      )
      |> assign(OpenGraph.og_image_assigns("tests"))
      |> assign(:reload_scheduled, false)

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  def handle_params(_params, uri, socket) do
    query = Query.query_params(uri)

    socket =
      socket
      |> assign(:uri, URI.new!("?" <> URI.encode_query(query)))
      |> assign(:page_path, URI.parse(uri).path)
      |> assign(:current_params, query)

    # The page is read once, when the socket connects; the disconnected
    # render shows its skeleton.
    {:noreply,
     if(connected?(socket),
       do: socket |> assign(:loading, false) |> assign_page(),
       else: assign(socket, :loading, true)
     )}
  end

  def handle_info({:test_created, _test_run}, %{assigns: %{reload_scheduled: true}} = socket), do: {:noreply, socket}

  def handle_info({:test_created, _test_run}, socket) do
    Process.send_after(self(), :reload, @reload_delay)
    {:noreply, assign(socket, :reload_scheduled, true)}
  end

  def handle_info(:reload, socket) do
    {:noreply, socket |> assign(:reload_scheduled, false) |> assign_page()}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  defp assign_page(%{assigns: %{selected_project: project, current_params: query}} = socket) do
    page =
      History.recent_commits_page(project, after: query["after"], before: query["before"], page_size: @page_size)

    socket
    |> assign(:commit_rows, Enum.map(page.commits, &Map.put(&1, :id, &1.git_commit_sha)))
    |> assign(:commits_meta, Map.take(page, [:has_next_page?, :has_previous_page?, :start_cursor, :end_cursor]))
  end

  @doc "A commit's page, whose back button leads here as shown."
  def commit_href(%{selected_account: account, selected_project: project, page_path: path, uri: uri}, sha) do
    from = if uri.query in [nil, ""], do: path, else: path <> "?" <> uri.query
    "/#{account.name}/#{project.name}/tests/coverage/commits/#{encode_path(sha)}?" <> URI.encode_query(%{"from" => from})
  end

  @doc "The branch a commit's runs named, or a dash when they named none."
  def branch_label(%{git_branch: branch}) when branch not in [nil, ""], do: branch
  def branch_label(_row), do: "—"

  @doc "The pull request a commit's runs named, when they named one."
  def pull_request_label(%{pull_request_number: number}) when is_integer(number) and number > 0,
    do: dgettext("dashboard_tests", "Pull request #%{number}", number: number)

  def pull_request_label(_row), do: nil
end
