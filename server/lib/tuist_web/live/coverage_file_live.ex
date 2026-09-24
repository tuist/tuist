defmodule TuistWeb.CoverageFileLive do
  @moduledoc """
  One file's coverage at a commit, on a page of its own that leads back to
  the commit's page.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components

  alias Tuist.FeatureFlags
  alias Tuist.Tests.Coverage.Commits
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  @detail_tabs ~w(overview targets files runs)

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

  def handle_params(_params, uri, socket) do
    query = Query.query_params(uri)
    socket = socket |> assign(:file, nil) |> assign_scope(query)

    if connected?(socket),
      do: {:noreply, assign_file(socket)},
      else: {:noreply, socket}
  end

  defp assign_file(%{assigns: %{selected_project: project, path: path, scope: %{commit: sha}}} = socket) do
    socket
    |> assign(:loading, false)
    |> assign(:file, Commits.file_detail(project.id, sha, path))
  end

  defp assign_scope(%{assigns: %{selected_project: project, selected_account: account}} = socket, query) do
    sha = query["commit"]

    if sha in [nil, ""] or is_nil(Commits.summary(project.id, sha)) do
      raise NotFoundError, dgettext("dashboard_tests", "No run of commit %{sha} gathered coverage.", sha: sha || "")
    end

    tab = if query["tab"] in @detail_tabs, do: [{"tab", query["tab"]}], else: []

    socket
    |> assign(:loading, true)
    |> assign(:scope, %{commit: sha})
    |> assign(:back, %{
      label: dgettext("dashboard_tests", "Commit %{name}", name: short_sha(sha)),
      href: "/#{account.name}/#{project.name}/tests/coverage/commits/#{encode_path(sha)}?" <> URI.encode_query(tab)
    })
  end

  @doc "What the page's badge says it is read at."
  def scope_label(%{commit: sha}), do: short_sha(sha)
end
