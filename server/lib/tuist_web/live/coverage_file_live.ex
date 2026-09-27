defmodule TuistWeb.CoverageFileLive do
  @moduledoc """
  One file's coverage at a commit, on a page of its own that leads back to
  the page it was opened from. Opened from a branch (`?branch=`), it leads
  with the file's coverage over the branch's period, as the branch's page
  does for the whole branch; from a pull request or a commit, with the
  commit's figures.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components

  alias Tuist.FeatureFlags
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.History
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  @detail_tabs ~w(overview targets files runs)
  @widgets ~w(coverage covered_lines executable_lines)
  @function_sorts ~w(coverage name line covered_lines executions)
  # Counts rank most first; shares, names and lines ascend.
  @descending_function_sorts ~w(covered_lines executions)
  @page_size 20

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

    socket =
      socket
      |> assign(:uri, URI.new!("?" <> URI.encode_query(query)))
      |> assign(:file, nil)
      |> assign(:trend, nil)
      |> assign_scope(query)

    if connected?(socket),
      do: {:noreply, socket |> assign_file() |> assign_functions(query) |> assign_trend(query)},
      else: {:noreply, socket}
  end

  def handle_event("search-functions", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("functions-search", search) |> Query.drop("page")
    {:noreply, push_patch(socket, to: socket.assigns.current_path <> "?" <> query, replace: true)}
  end

  def handle_event(
        "coverage_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("coverage-date-range", "custom")
        |> Query.put("coverage-start-date", start_date)
        |> Query.put("coverage-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "coverage-date-range", preset)
      end

    {:noreply, push_patch(socket, to: socket.assigns.current_path <> "?" <> query)}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    query = Query.put(socket.assigns.uri.query, "analytics-selected-widget", selected_widget(widget))
    {:noreply, push_patch(socket, to: socket.assigns.current_path <> "?" <> query, replace: true)}
  end

  defp assign_file(%{assigns: %{selected_project: project, path: path, scope: %{commit: sha}}} = socket) do
    socket
    |> assign(:loading, false)
    |> assign(:file, Commits.file_detail(project.id, sha, path))
  end

  # A file has tens of functions, hundreds at most, all read with it, so they
  # are searched, sorted and paged here.
  defp assign_functions(%{assigns: %{file: file}} = socket, query) do
    search = String.trim(query["functions-search"] || "")
    sort_by = if query["functions-sort-by"] in @function_sorts, do: query["functions-sort-by"], else: "coverage"

    sort_order =
      if query["functions-sort-order"] in ~w(asc desc),
        do: query["functions-sort-order"],
        else: default_function_order(sort_by)

    functions =
      (file && file.functions)
      |> List.wrap()
      |> Enum.filter(&(search == "" or String.contains?(String.downcase(&1.name), String.downcase(search))))
      |> sort_functions(sort_by, String.to_existing_atom(sort_order))

    total_pages = max(1, ceil(length(functions) / @page_size))
    page = min(Query.bounded_page(query["page"]), total_pages)

    socket
    |> assign(
      :function_rows,
      functions
      |> Enum.slice((page - 1) * @page_size, @page_size)
      |> Enum.map(&Map.put(&1, :id, "function-#{&1.line_number}-#{&1.name}"))
    )
    |> assign(:functions_meta, %{current_page: page, total_pages: total_pages})
    |> assign(:functions_search, search)
    |> assign(:functions_sort_by, sort_by)
    |> assign(:functions_sort_order, sort_order)
  end

  defp default_function_order(sort_by) when sort_by in @descending_function_sorts, do: "desc"
  defp default_function_order(_sort_by), do: "asc"

  defp sort_functions(functions, "name", direction), do: Enum.sort_by(functions, &{&1.name, &1.line_number}, direction)
  defp sort_functions(functions, "line", direction), do: Enum.sort_by(functions, &{&1.line_number, &1.name}, direction)

  defp sort_functions(functions, "executions", direction),
    do: Enum.sort_by(functions, &{&1.execution_count, &1.line_number}, direction)

  defp sort_functions(functions, "covered_lines", direction),
    do: sort_known_coverage(functions, &{&1.covered_lines, &1.line_number}, direction)

  defp sort_functions(functions, "coverage", direction),
    do: sort_known_coverage(functions, &{&1.covered_lines / max(&1.executable_lines, 1), &1.line_number}, direction)

  # A function whose covered lines are unknown has nothing to rank by, so it
  # comes last either way.
  defp sort_known_coverage(functions, key, direction) do
    {unknown, known} = Enum.split_with(functions, &is_nil(&1.covered_lines))
    Enum.sort_by(known, key, direction) ++ Enum.sort_by(unknown, & &1.line_number)
  end

  @doc "The functions list's sorts, with their labels, in the order of the table's columns."
  def function_sorts,
    do: [
      {"name", dgettext("dashboard_tests", "Function")},
      {"line", dgettext("dashboard_tests", "Line")},
      {"covered_lines", dgettext("dashboard_tests", "Covered lines")},
      {"executions", dgettext("dashboard_tests", "Executions")},
      {"coverage", dgettext("dashboard_tests", "Coverage")}
    ]

  @doc "The query that sorts the functions by a column: the other order when it already does, the column's own otherwise."
  def functions_sort_patch(%{uri: uri, functions_sort_by: sort_by, functions_sort_order: order}, column) do
    order =
      cond do
        sort_by != column -> default_function_order(column)
        order == "asc" -> "desc"
        true -> "asc"
      end

    "?" <>
      (uri.query
       |> Query.put("functions-sort-by", column)
       |> Query.put("functions-sort-order", order)
       |> Query.drop("page"))
  end

  # A branch's file leads with its coverage over the branch's period.
  defp assign_trend(%{assigns: %{scope: %{branch: nil}}} = socket, _query), do: socket

  defp assign_trend(%{assigns: %{selected_project: project, path: path, scope: %{branch: branch}}} = socket, query) do
    %{preset: preset, period: period} = DatePicker.date_picker_params(query, "coverage", default_preset: "last-30-days")
    points = History.file_points(project, branch, path, DatePicker.period_opts(period))

    assign(socket, :trend, %{
      branch: branch,
      points: chart_points(points, period),
      latest: List.last(points),
      trends: %{
        "coverage" => period_trend(points),
        "covered_lines" => count_trend(points, :covered_lines),
        "executable_lines" => count_trend(points, :executable_lines)
      },
      selected_widget: selected_widget(query["analytics-selected-widget"]),
      preset: preset,
      period: period
    })
  end

  defp selected_widget(widget) when widget in @widgets, do: widget
  defp selected_widget(_widget), do: "coverage"

  defp assign_scope(%{assigns: %{selected_project: project, selected_account: account}} = socket, query) do
    sha = query["commit"]

    if sha in [nil, ""] or is_nil(Commits.summary(project.id, sha)) do
      raise NotFoundError, dgettext("dashboard_tests", "No run of commit %{sha} gathered coverage.", sha: sha || "")
    end

    tab = if query["tab"] in @detail_tabs, do: [{"tab", query["tab"]}], else: []

    socket
    |> assign(:loading, true)
    |> assign(:scope, %{
      commit: sha,
      branch: blank_to_nil(query["branch"]),
      pull_request: blank_to_nil(query["pull-request"])
    })
    |> assign(
      :back,
      back_to(query["from"], account.name, project.name) ||
        %{
          label: dgettext("dashboard_tests", "Commit %{name}", name: short_sha(sha)),
          href: "/#{account.name}/#{project.name}/tests/coverage/commits/#{encode_path(sha)}?" <> URI.encode_query(tab)
        }
    )
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  @doc "What the page's badge says it is read at."
  def scope_label(%{commit: sha}), do: short_sha(sha)
end
