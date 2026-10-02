defmodule TuistWeb.CoverageFileLive do
  @moduledoc """
  One file's coverage on a branch over a period: its figures and functions
  at the branch's latest complete commit in the period, and its coverage
  over the branch's complete commits there (`History.trend_points/3`,
  `History.file_points/3`). Opened from a commit's page (`commit`), it is
  that commit's file instead: its figures and functions alone, with no
  period to pick, and a link to the file on the default branch. The branch is the one its link names (`branch`, the
  project's default one unless set), and the period is picked in the header
  with the Code Coverage page's picker. It leads back to
  the page it was opened from (`from`), or to the Code Coverage page.
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Coverage.Components

  alias Tuist.FeatureFlags
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.History
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

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
    %{preset: preset, period: period} = DatePicker.date_picker_params(query, "coverage", default_preset: "last-30-days")

    socket =
      socket
      |> assign(:uri, URI.new!("?" <> URI.encode_query(query)))
      |> assign(:current_params, query)
      |> assign(:coverage_preset, preset)
      |> assign(:coverage_period, period)
      |> assign(:branch, selected_branch(query["branch"], socket.assigns.selected_project))
      |> assign(:commit, blank_to_nil(query["commit"]))
      |> assign(:file, nil)
      |> assign(:trend, nil)
      |> assign(:loading, true)
      |> assign_back(query)

    if connected?(socket),
      do:
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign_file(query)
         |> assign_functions(query)},
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

  # At a commit, the file is that commit's, figures and functions alone. On a
  # branch, its figures and functions are its own at the branch's latest
  # complete commit in the period, and its trend is over the branch's
  # complete commits there that compiled it.
  defp assign_file(%{assigns: %{selected_project: project, path: path, commit: sha}} = socket, _query)
       when is_binary(sha), do: assign(socket, :file, Commits.file_detail(project.id, sha, path))

  defp assign_file(%{assigns: %{selected_project: project, path: path, branch: branch}} = socket, query) do
    %{grouping: grouping, points: points} =
      History.trend_points(project, branch, DatePicker.period_opts(socket.assigns.coverage_period))

    case List.last(points) do
      nil ->
        socket

      %{git_commit_sha: sha} ->
        file = Commits.file_detail(project.id, sha, path)
        file_points = History.file_points(project, path, points)

        socket
        |> assign(:file, file)
        |> assign(:trend, file && trend(file, sha, file_points, grouping, query))
    end
  end

  defp trend(file, sha, points, grouping, query) do
    %{
      latest: %{
        git_commit_sha: sha,
        coverage: Coverage.percentage(file.covered_lines, file.executable_lines),
        covered_lines: file.covered_lines,
        executable_lines: file.executable_lines
      },
      points: points,
      grouping: grouping,
      trends: %{
        "coverage" => period_trend(points),
        "covered_lines" => count_trend(points, :covered_lines),
        "executable_lines" => count_trend(points, :executable_lines)
      },
      selected_widget: selected_widget(query["analytics-selected-widget"])
    }
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

  defp selected_widget(widget) when widget in @widgets, do: widget
  defp selected_widget(_widget), do: "coverage"

  defp assign_back(%{assigns: %{selected_project: project, selected_account: account}} = socket, query) do
    assign(socket, :back, back_to(query["from"], account.name, project.name) || default_back(socket, query))
  end

  # Without `from`, a commit's file leads to the commit's Files tab, and a
  # branch's to the Code Coverage page on the same branch and period.
  defp default_back(%{assigns: %{commit: sha, selected_project: project, selected_account: account}}, _query)
       when is_binary(sha) do
    %{
      label: dgettext("dashboard_tests", "Commit %{name}", name: short_sha(sha)),
      href: "/#{account.name}/#{project.name}/tests/coverage/commits/#{encode_path(sha)}?tab=files"
    }
  end

  defp default_back(%{assigns: %{selected_project: project, selected_account: account}}, query) do
    %{
      label: dgettext("dashboard_tests", "Code coverage"),
      href: with_shared_query("/#{account.name}/#{project.name}/tests/coverage", query)
    }
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
