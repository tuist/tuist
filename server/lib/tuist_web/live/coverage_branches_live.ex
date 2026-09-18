defmodule TuistWeb.CoverageBranchesLive do
  @moduledoc """
  Every branch that gathered coverage, searchable: where a reader goes to
  find a branch other than the default one, which the project's Code
  Coverage page (`TuistWeb.CoverageLive`) covers on its own. A branch pushed
  for a pull request carries its number and leads to the pull request, which
  has the diff to say more; every other branch leads to its own page
  (`TuistWeb.CoverageDetailLive`).
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components
  import TuistWeb.Helpers.TestLabels

  alias Tuist.FeatureFlags
  alias Tuist.Tests.Coverage.History
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @page_size 20

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    if !FeatureFlags.xcode_coverage_enabled?(account) do
      raise NotFoundError, dgettext("dashboard_tests", "Code coverage is not enabled for this account.")
    end

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_tests", "Branches")} · #{account.name}/#{project.name} · Tuist")
      |> assign(OpenGraph.og_image_assigns("tests"))

    {:ok, socket}
  end

  def handle_params(_params, uri, socket) do
    query = Query.query_params(uri)

    {:noreply,
     socket
     |> assign(:uri, URI.new!("?" <> URI.encode_query(query)))
     |> assign_branches(query)}
  end

  def handle_event(
        "search-branches",
        %{"search" => search},
        %{assigns: %{selected_account: account, selected_project: project, uri: uri}} = socket
      ) do
    query = uri.query |> Query.put("search", search) |> Query.drop("page")

    {:noreply,
     push_patch(socket,
       to: "/#{account.name}/#{project.name}/tests/coverage/branches?#{query}",
       replace: true
     )}
  end

  defp assign_branches(%{assigns: %{selected_project: project}} = socket, query) do
    search = query["search"] || ""

    page =
      History.refs(project,
        search: search,
        page: Query.bounded_page(query["page"]),
        page_size: @page_size
      )

    socket
    |> assign(:search, search)
    |> assign(:branch_rows, Enum.map(page.refs, &Map.put(&1, :id, "ref-" <> &1.name)))
    |> assign(:branches_meta, %{current_page: page.page, total_pages: page.total_pages})
  end
end
