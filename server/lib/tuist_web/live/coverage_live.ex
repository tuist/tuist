defmodule TuistWeb.CoverageLive do
  @moduledoc """
  The project's Code Coverage page: the default branch's coverage over time
  from its full runs, every branch's coverage, the pull requests' coverage
  against their baselines, the least covered files and targets, the runs that
  gathered coverage, and the settings (gates, Git history, retention).
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection

  alias Tuist.Authorization
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.GitHistory
  alias Tuist.Projects
  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Coverage.Gates
  alias Tuist.Tests.Coverage.History
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @tabs ~w(overview branches pull-requests files runs settings)
  @page_size 20

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    if !FeatureFlags.xcode_coverage_enabled?(account) do
      raise NotFoundError, dgettext("dashboard_tests", "Code coverage is not enabled for this account.")
    end

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_tests", "Code Coverage")} · #{account.name}/#{project.name} · Tuist")
      |> assign(OpenGraph.og_image_assigns("tests"))
      |> assign(
        :can_update_settings,
        Authorization.authorize(:project_update, socket.assigns.current_user, project) == :ok
      )

    if connected?(socket) do
      Tuist.PubSub.subscribe("#{account.name}/#{project.name}")
    end

    {:ok, socket}
  end

  def handle_params(params, uri, %{assigns: %{selected_project: project}} = socket) do
    query = uri |> Query.query_params() |> Map.delete("pull_request_number")
    uri = URI.new!("?" <> URI.encode_query(query))
    %{preset: preset, period: period} = DatePicker.date_picker_params(query, "coverage", default_preset: "last-30-days")

    socket =
      socket
      |> assign(:uri, uri)
      |> assign(:current_params, query)
      |> assign(:coverage_preset, preset)
      |> assign(:coverage_period, period)
      |> assign(:branch, query["branch"] || project.default_branch)

    socket =
      case socket.assigns.live_action do
        :pull_request -> assign_pull_request(socket, params["pull_request_number"], query)
        _ -> socket |> assign(:tab, tab(query["tab"])) |> assign_tab(query)
      end

    {:noreply, socket}
  end

  defp tab(value) when value in @tabs, do: value
  defp tab(_value), do: "overview"

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

    {:noreply, push_patch(socket, to: "?" <> Query.drop(query, "page"))}
  end

  def handle_event("save_settings", params, %{assigns: %{can_update_settings: true}} = socket) do
    update_settings(socket, %{
      coverage_gate_min_patch_coverage: number_or_nil(params["min_patch_coverage"]),
      coverage_gate_max_total_drop: number_or_nil(params["max_total_drop"]),
      git_history_window_days: integer_or_nil(params["git_history_window_days"]),
      git_history_window_commits: integer_or_nil(params["git_history_window_commits"])
    })
  end

  def handle_event("save_settings", _params, socket), do: {:noreply, socket}

  @toggles ~w(coverage_gates_enabled coverage_patch_partial_runs git_history_provider_fallback)

  def handle_event("toggle_setting", %{"setting" => setting}, %{assigns: %{can_update_settings: true}} = socket)
      when setting in @toggles do
    key = String.to_existing_atom(setting)
    current = Map.get(socket.assigns.selected_project, key) || false
    update_settings(socket, %{key => not current})
  end

  def handle_event("toggle_setting", _params, socket), do: {:noreply, socket}

  defp update_settings(%{assigns: %{selected_project: project}} = socket, attrs) do
    case Projects.update_project(project, attrs) do
      {:ok, project} ->
        {:noreply,
         socket
         |> assign(:selected_project, project)
         |> assign_settings()
         |> put_flash(:info, dgettext("dashboard_tests", "Coverage settings saved."))}

      {:error, changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_tests", "Could not save the coverage settings: %{errors}", errors: errors(changeset))
         )}
    end
  end

  def handle_info({:test_created, _test_run}, %{assigns: %{live_action: :pull_request}} = socket) do
    {:noreply,
     assign_pull_request(socket, Integer.to_string(socket.assigns.pull_request_number), socket.assigns.current_params)}
  end

  def handle_info({:test_created, _test_run}, socket) do
    {:noreply, assign_tab(socket, socket.assigns.current_params)}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  defp assign_tab(socket, query) do
    socket = assign_scope(socket, query)

    case socket.assigns.tab do
      "overview" -> assign_overview(socket)
      "branches" -> assign_branches(socket)
      "pull-requests" -> assign_pull_requests(socket, query)
      "files" -> assign_files(socket, query)
      "runs" -> assign_runs(socket, query)
      "settings" -> assign_settings(socket)
    end
  end

  # The branch and scheme every figure is for: the scheme defaults to the one
  # with most full runs on the branch in the period.
  defp assign_scope(%{assigns: %{selected_project: project, branch: branch}} = socket, query) do
    schemes = History.schemes(project.id, branch, period_opts(socket))
    scheme_names = Enum.map(schemes, & &1.scheme)

    scheme =
      cond do
        query["scheme"] in scheme_names -> query["scheme"]
        scheme_names == [] -> query["scheme"]
        true -> hd(scheme_names)
      end

    socket
    |> assign(:schemes, scheme_names)
    |> assign(:scheme, scheme)
    |> assign(:branches, History.branch_names(project.id, period_opts(socket)))
  end

  defp assign_overview(%{assigns: %{selected_project: project, branch: branch, scheme: scheme}} = socket) do
    points = if scheme, do: History.branch_points(project.id, branch, scheme, period_opts(socket)), else: []
    latest = List.last(points)
    first = List.first(points)

    socket
    |> assign(:points, points)
    |> assign(:latest, latest)
    |> assign(:trend, if(latest && first && latest != first, do: Float.round(latest.coverage - first.coverage, 1)))
  end

  defp assign_branches(%{assigns: %{selected_project: project, scheme: scheme}} = socket) do
    branches = if scheme, do: History.branches(project, scheme, period_opts(socket)), else: []
    assign(socket, :branch_rows, Enum.map(branches, &Map.put(&1, :id, &1.git_branch)))
  end

  defp assign_pull_requests(%{assigns: %{selected_project: project}} = socket, query) do
    page = Query.bounded_page(query["page"])

    {rows, count} =
      History.pull_requests(project.id, Keyword.merge(period_opts(socket), page: page, page_size: @page_size))

    rows =
      Enum.map(rows, fn row ->
        change =
          with {:ok, run} <- Tests.get_test(row.test_run_id),
               false <- row.partial,
               {:ok, baseline} <- Comparison.baseline(project, run) do
            {:delta,
             Float.round(row.coverage - Coverage.percentage(baseline.covered_lines, baseline.executable_lines), 1)}
          else
            true -> {:partial, nil}
            {:error, reason} -> {:no_baseline, reason}
            _ -> {:no_baseline, nil}
          end

        row |> Map.put(:id, "#{row.pull_request_number}-#{row.scheme}") |> Map.put(:change, change)
      end)

    socket
    |> assign(:pull_request_rows, rows)
    |> assign(:pull_requests_meta, %{current_page: page, total_pages: max(1, ceil(count / @page_size))})
  end

  defp assign_files(%{assigns: %{selected_project: project, branch: branch, scheme: scheme}} = socket, query) do
    page = Query.bounded_page(query["page"])
    latest = if scheme, do: History.latest(project.id, branch, scheme, period_opts(socket))

    {targets, files, count} =
      if latest do
        [targets, {files, count}] =
          Tuist.Tasks.parallel_tasks([
            fn -> Coverage.targets_for_run(project.id, latest.test_run_id) end,
            fn -> Coverage.list_files(project.id, latest.test_run_id, page, @page_size) end
          ])

        {targets, files, count}
      else
        {[], [], 0}
      end

    socket
    |> assign(:latest, latest)
    |> assign(:targets, Enum.map(targets, &Map.put(&1, :id, "target-" <> &1.name)))
    |> assign(:files, Enum.map(files, &Map.put(&1, :id, "file-" <> &1.path)))
    |> assign(:files_meta, %{current_page: page, total_pages: max(1, ceil(count / @page_size))})
  end

  defp assign_runs(%{assigns: %{selected_project: project}} = socket, query) do
    {start_datetime, end_datetime} = socket.assigns.coverage_period
    kind = if query["coverage"] in ~w(full partial), do: String.to_existing_atom(query["coverage"]), else: :any

    options = %{
      filters: [
        %{field: :project_id, op: :==, value: project.id},
        %{field: :ran_at, op: :>=, value: start_datetime},
        %{field: :ran_at, op: :<=, value: end_datetime}
      ],
      order_by: [:ran_at],
      order_directions: [:desc]
    }

    options =
      cond do
        query["before"] -> options |> Map.put(:last, @page_size) |> Map.put(:before, query["before"])
        query["after"] -> options |> Map.put(:first, @page_size) |> Map.put(:after, query["after"])
        true -> Map.put(options, :first, @page_size)
      end

    {runs, meta} = Tests.list_test_runs(options, project_id: project.id, coverage: {:in, kind})

    socket
    |> assign(:runs_kind, Atom.to_string(kind))
    |> assign(:runs, runs)
    |> assign(:runs_meta, meta)
    |> assign(:totals_by_run, Coverage.totals_for_runs(project.id, Enum.map(runs, & &1.id)))
  end

  defp assign_settings(%{assigns: %{selected_project: project}} = socket) do
    retention = Environment.coverage_retention_days()

    socket
    |> assign(:gates, Gates.settings(project))
    |> assign(:git_history, GitHistory.settings(project))
    |> assign(:git_history_defaults, GitHistory.settings(nil))
    |> assign(:retention, retention)
  end

  defp assign_pull_request(%{assigns: %{selected_project: project}} = socket, number, query) do
    number =
      case Integer.parse(number || "") do
        {number, ""} -> number
        _ -> raise NotFoundError, dgettext("dashboard_tests", "Pull request not found.")
      end

    runs = History.pull_request_runs(project.id, number)

    if runs == [] do
      raise NotFoundError,
            dgettext("dashboard_tests", "No test run of pull request #%{number} gathered coverage.", number: number)
    end

    selected = Enum.find(runs, hd(runs), &(&1.test_run_id == query["run"]))
    {:ok, run} = Tests.get_test(selected.test_run_id)

    comparison =
      Comparison.compare(project, run,
        run_summary: %{
          partial: selected.partial,
          covered_lines: selected.covered_lines,
          executable_lines: selected.executable_lines
        }
      )

    files_page = Query.bounded_page(query["files-page"])
    files_pages = max(1, ceil(length(comparison.files) / @page_size))

    socket
    |> assign(:pull_request_number, number)
    |> assign(:pull_request_runs, runs)
    |> assign(:run, run)
    |> assign(:pr_selection, selected)
    |> assign(:comparison, comparison)
    |> assign(:target_rows, Enum.map(comparison.targets, &Map.put(&1, :id, "target-" <> &1.name)))
    |> assign(
      :file_rows,
      comparison.files |> Enum.slice((files_page - 1) * @page_size, @page_size) |> Enum.map(&Map.put(&1, :id, &1.path))
    )
    |> assign(:files_meta, %{current_page: min(files_page, files_pages), total_pages: files_pages})
    |> assign(:patch_rows, patch_rows(comparison.patch))
    |> assign(:skipped_rows, skipped_rows(comparison.patch))
  end

  defp patch_rows(%{status: :available, files: files}), do: Enum.map(files, &Map.put(&1, :id, "patch-" <> &1.path))
  defp patch_rows(_patch), do: []

  defp skipped_rows(%{status: :available, skipped: skipped}),
    do: Enum.map(skipped, &Map.put(&1, :id, "skipped-" <> &1.path))

  defp skipped_rows(_patch), do: []

  defp period_opts(%{assigns: %{coverage_period: {start_datetime, end_datetime}}}) do
    [since: DateTime.to_naive(start_datetime), until: DateTime.to_naive(end_datetime)]
  end

  defp number_or_nil(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp number_or_nil(_value), do: nil

  defp integer_or_nil(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp integer_or_nil(_value), do: nil

  defp errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc -> String.replace(acc, "%{#{key}}", to_string(value)) end)
    end)
    |> Enum.map_join(", ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  attr :title, :string, required: true
  attr :get_started_href, :string, default: nil
  attr :rest, :global

  defp coverage_empty(assigns) do
    ~H"""
    <.empty_card_section title={@title} get_started_href={@get_started_href} {@rest}>
      <:image>
        <img
          src={~p"/images/empty_line_chart_light.png"}
          data-theme="light"
          loading="lazy"
          decoding="async"
        />
        <img
          src={~p"/images/empty_line_chart_dark.png"}
          data-theme="dark"
          loading="lazy"
          decoding="async"
        />
      </:image>
    </.empty_card_section>
    """
  end

  attr :covered, :integer, required: true
  attr :executable, :integer, required: true

  defp coverage_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="text">
      <div data-part="coverage-cell">
        <.progress_bar value={@covered} max={max(@executable, 1)} />
        <span data-part="percentage">{Coverage.percentage(@covered, @executable)}%</span>
      </div>
    </div>
    """
  end

  attr :delta, :float, default: nil

  defp change_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="text">
      <.badge
        :if={@delta}
        style="light-fill"
        size="small"
        color={change_color({:delta, @delta})}
        label={"#{signed(@delta)} pp"}
      />
      <span :if={is_nil(@delta)} data-part="label">—</span>
    </div>
    """
  end

  attr :totals, :map, default: nil

  defp totals_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="text">
      <span data-part="label">
        {if @totals,
          do: "#{Coverage.percentage(@totals.covered_lines, @totals.executable_lines)}%",
          else: "—"}
      </span>
      <.badge
        :for={{color, label} <- List.wrap(coverage_badge(@totals))}
        style="light-fill"
        size="small"
        color={color}
        label={label}
      />
    </div>
    """
  end

  @doc false
  def signed(nil), do: "—"
  def signed(value) when value > 0, do: "+#{value}"
  def signed(value), do: "#{value}"

  @doc false
  def short_sha(sha), do: String.slice(sha || "", 0, 7)

  @doc false
  def change_label({:delta, delta}), do: "#{signed(delta)} pp"
  def change_label({:partial, _}), do: dgettext("dashboard_tests", "Not compared (partial run)")

  def change_label({:no_baseline, reason}),
    do: dgettext("dashboard_tests", "No baseline: %{reason}", reason: reason_label(reason))

  @doc false
  def change_color({:delta, delta}) when delta < 0, do: "destructive"
  def change_color({:delta, delta}) when delta > 0, do: "success"
  def change_color(_change), do: "neutral"

  @doc false
  def reason_label(%{kind: :no_merge_base, base_branch: branch} = reason),
    do: with_detail(dgettext("dashboard_tests", "the merge base with %{branch} is unknown", branch: branch), reason)

  def reason_label(%{kind: :no_history, commit: sha} = reason),
    do:
      with_detail(
        dgettext("dashboard_tests", "commit %{sha} is not in the project's Git history", sha: short_sha(sha)),
        reason
      )

  def reason_label(%{kind: :no_full_runs, base_branch: branch, scheme: scheme, window_days: days}),
    do:
      dgettext("dashboard_tests", "no full coverage run of %{scheme} on %{branch} in the last %{days} days",
        scheme: scheme,
        branch: branch,
        days: days
      )

  def reason_label(%{kind: :no_ancestor_run, base_branch: branch, commit: sha, window_commits: commits}),
    do:
      dgettext("dashboard_tests", "no full run on %{branch} within %{commits} commits before %{sha}",
        branch: branch,
        commits: commits,
        sha: short_sha(sha)
      )

  def reason_label(%{reason: :partial_run}), do: dgettext("dashboard_tests", "the run skipped tests")
  def reason_label(%{kind: :partial_run}), do: dgettext("dashboard_tests", "the run skipped tests")

  def reason_label(%{reason: :no_history} = reason),
    do: with_detail(dgettext("dashboard_tests", "the run's Git history was not collected"), reason)

  def reason_label(_reason), do: dgettext("dashboard_tests", "unknown")

  defp with_detail(text, %{detail: detail}) when is_binary(detail) and detail != "", do: "#{text} (#{detail})"
  defp with_detail(text, _reason), do: text

  @doc false
  def skipped_reason_label(:stale), do: dgettext("dashboard_tests", "Measured on another version of the file")
  def skipped_reason_label(:no_line_data), do: dgettext("dashboard_tests", "No per-line data in the run")
  def skipped_reason_label(:truncated), do: dgettext("dashboard_tests", "Diff too large to record its lines")
  def skipped_reason_label(:not_instrumented), do: dgettext("dashboard_tests", "Not compiled into any tested target")

  @doc false
  def line_ranges(nil), do: dgettext("dashboard_tests", "Unknown")
  def line_ranges([]), do: dgettext("dashboard_tests", "None")

  def line_ranges(ranges) do
    Enum.map_join(ranges, ", ", fn
      {line, line} -> Integer.to_string(line)
      {first, last} -> "#{first}–#{last}"
    end)
  end

  @doc false
  def coverage_badge(nil), do: nil
  def coverage_badge(%{partial: true}), do: {"warning", dgettext("dashboard_tests", "P")}
  def coverage_badge(_totals), do: {"success", dgettext("dashboard_tests", "F")}
end
