defmodule TuistWeb.CoverageLive do
  @moduledoc """
  The project's Code Coverage page, commit by commit: a branch's coverage
  over time from its chained commits, the commits behind it with the
  unmeasured ones in place, where the coverage is thinnest at its latest
  commit, and every branch and pull request that gathered coverage. Each
  row leads to one commit's page, which compares it with its baseline and,
  when the project has gates, says how they were decided.

  Its settings live under the project's settings
  (`TuistWeb.ProjectCoverageSettingsLive`).
  """
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Helpers.TestLabels

  alias Tuist.FeatureFlags
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Coverage.Gates
  alias Tuist.Tests.Coverage.History
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @page_size 20
  # How many rows the cards that only point somewhere else hold.
  @preview_size 5

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

  def handle_params(params, uri, %{assigns: %{selected_project: project}} = socket) do
    query = uri |> Query.query_params() |> Map.drop(["pull_request_number", "git_commit_sha"])
    uri = URI.new!("?" <> URI.encode_query(query))
    %{preset: preset, period: period} = DatePicker.date_picker_params(query, "coverage", default_preset: "last-30-days")

    socket =
      socket
      |> assign(:uri, uri)
      |> assign(:current_params, query)
      |> assign(:coverage_preset, preset)
      |> assign(:coverage_period, period)
      |> assign(:branch, query["branch"] || project.default_branch)
      |> assign(:scheme, blank_to_nil(query["scheme"]))

    socket =
      case socket.assigns.live_action do
        :pull_request -> assign_pull_request(socket, params["pull_request_number"], query)
        :commit -> assign_commit_page(socket, params["git_commit_sha"], query)
        _ -> assign_page(socket, query)
      end

    {:noreply, socket}
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

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

  def handle_event(
        "search-refs",
        %{"search" => search},
        %{assigns: %{selected_account: account, selected_project: project, uri: uri}} = socket
      ) do
    query = uri.query |> Query.put("refs-search", search) |> Query.drop("refs-page")

    {:noreply,
     push_patch(socket,
       to: "/#{account.name}/#{project.name}/tests/coverage?#{query}",
       replace: true
     )}
  end

  def handle_info({:test_created, _test_run}, %{assigns: %{live_action: :pull_request}} = socket) do
    {:noreply,
     assign_pull_request(socket, Integer.to_string(socket.assigns.pull_request_number), socket.assigns.current_params)}
  end

  def handle_info({:test_created, _test_run}, %{assigns: %{live_action: :commit}} = socket) do
    {:noreply, assign_commit_page(socket, socket.assigns.commit_sha, socket.assigns.current_params)}
  end

  def handle_info({:test_created, _test_run}, socket) do
    {:noreply, assign_page(socket, socket.assigns.current_params)}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  # The page holds two sections: what the branch's coverage does over the
  # period, and every branch and pull request that gathered any.
  defp assign_page(socket, query) do
    socket
    |> assign_scope()
    |> assign_analytics()
    |> assign_commits(query)
    |> assign_gaps()
    |> assign_refs(query)
  end

  # The branch every figure is for, and the schemes measured on it: a
  # scheme narrows the figures to its own runs; none pools the commit.
  defp assign_scope(%{assigns: %{selected_project: project, branch: branch}} = socket) do
    schemes = project |> History.schemes(branch, period_opts(socket)) |> Enum.map(& &1.scheme)

    socket
    |> assign(:schemes, schemes)
    |> assign(:branches, History.branch_names(project.id, period_opts(socket)))
  end

  defp assign_analytics(%{assigns: %{selected_project: project, branch: branch, scheme: scheme}} = socket) do
    points = History.branch_points(project, branch, Keyword.put(period_opts(socket), :scheme, scheme))
    latest = List.last(points)
    first = List.first(points)

    socket
    |> assign(:points, points)
    |> assign(:latest, latest)
    |> assign(:trend, if(latest && first && latest != first, do: Float.round(latest.coverage - first.coverage, 1)))
  end

  defp assign_commits(%{assigns: %{selected_project: project, branch: branch}} = socket, query) do
    page =
      History.commit_page(
        project,
        branch,
        Keyword.merge(period_opts(socket), page: Query.bounded_page(query["commits-page"]), page_size: @page_size)
      )

    socket
    |> assign(:commit_rows, Enum.map(page.commits, &Map.put(&1, :id, &1.git_commit_sha)))
    |> assign(:commits_meta, %{current_page: page.page, total_pages: page.total_pages, total_count: page.total_count})
    |> assign(:commits_ordered_by, page.ordered_by)
  end

  # Where the coverage is thinnest at the branch's latest commit: the least
  # covered files, and the tracked files no scheme measured at all.
  defp assign_gaps(%{assigns: %{selected_project: project, latest: latest}} = socket) do
    {files, unmeasured} =
      if latest do
        [{files, _count}, unmeasured] =
          Tuist.Tasks.parallel_tasks([
            fn -> Commits.list_files(project.id, latest.git_commit_sha, 1, @preview_size) end,
            fn -> Commits.unmeasured_files(project, latest.git_commit_sha, limit: @preview_size) end
          ])

        {files, unmeasured}
      else
        {[], []}
      end

    socket
    |> assign(:gap_files, Enum.map(files, &Map.put(&1, :id, "gap-" <> &1.path)))
    |> assign(:unmeasured_files, Enum.map(unmeasured, &%{id: "unmeasured-" <> &1, path: &1}))
  end

  defp assign_refs(%{assigns: %{selected_project: project}} = socket, query) do
    search = query["refs-search"] || ""

    page =
      History.refs(
        project,
        Keyword.merge(period_opts(socket),
          search: search,
          page: Query.bounded_page(query["refs-page"]),
          page_size: @page_size
        )
      )

    socket
    |> assign(:refs_search, search)
    |> assign(:ref_rows, Enum.map(page.refs, &Map.put(&1, :id, &1.kind <> "-" <> &1.name)))
    |> assign(:refs_meta, %{current_page: page.page, total_pages: page.total_pages, total_count: page.total_count})
  end

  defp assign_pull_request(%{assigns: %{selected_project: project}} = socket, number, query) do
    number =
      case Integer.parse(number || "") do
        {number, ""} -> number
        _ -> raise NotFoundError, dgettext("dashboard_tests", "Pull request not found.")
      end

    commits = History.pull_request_commits(project.id, number)

    if commits == [] do
      raise NotFoundError,
            dgettext("dashboard_tests", "No test run of pull request #%{number} gathered coverage.", number: number)
    end

    selected = Enum.find(commits, hd(commits), &(&1.git_commit_sha == query["commit"]))

    socket
    |> assign(:pull_request_number, number)
    |> assign(:pull_request_commits, commits)
    |> assign(:pr_selection, selected)
    |> assign_commit_view(selected.git_commit_sha, query)
  end

  defp assign_commit_page(%{assigns: %{selected_project: project}} = socket, sha, query) do
    if sha in [nil, ""] or is_nil(Commits.summary(project.id, sha)) do
      raise NotFoundError, dgettext("dashboard_tests", "No run of commit %{sha} gathered coverage.", sha: sha || "")
    end

    assign_commit_view(socket, sha, query)
  end

  # What one commit's view shows, whether reached from a pull request or on
  # its own: its comparison, targets and changed files, and its runs.
  defp assign_commit_view(%{assigns: %{selected_project: project}} = socket, sha, query) do
    head = Comparison.from_commit(project, sha)
    comparison = Comparison.compare(project, head)
    files_page = Query.bounded_page(query["files-page"])
    files_pages = max(1, ceil(length(comparison.files) / @page_size))

    socket
    |> assign(:commit_sha, sha)
    |> assign(:head, head)
    |> assign(:comparison, comparison)
    |> assign(:gates, Gates.settings(project))
    |> assign(:gate_verdict, if(project.coverage_gates_enabled, do: Gates.evaluate(project, comparison)))
    |> assign(:commit_runs, Commits.runs(project.id, sha))
    |> assign(:scheme_rows, Enum.map(comparison.schemes, &Map.put(&1, :id, "scheme-" <> &1.scheme)))
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

  attr :commit, :map, required: true

  # The schemes that measured a commit, the partial ones marked.
  defp measured_by_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="text">
      <div data-part="tags">
        <.badge
          :for={scheme <- @commit.schemes}
          style="light-fill"
          size="small"
          color={if scheme in @commit.partial_schemes, do: "warning", else: "neutral"}
          label={if scheme in @commit.partial_schemes, do: "#{scheme} · P", else: scheme}
        />
      </div>
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
  def change_color({:delta, delta}) when delta < 0, do: "destructive"
  def change_color({:delta, delta}) when delta > 0, do: "success"
  def change_color(_change), do: "neutral"

  @doc false
  def completeness_label(%{measured: false}), do: dgettext("dashboard_tests", "Not measured")
  def completeness_label(%{complete: true, completeness: "signal"}), do: dgettext("dashboard_tests", "Complete")
  def completeness_label(%{complete: true}), do: dgettext("dashboard_tests", "Complete")
  def completeness_label(%{chained: true}), do: dgettext("dashboard_tests", "Comparable")
  def completeness_label(_commit), do: dgettext("dashboard_tests", "Not chained")

  @doc false
  def completeness_color(%{measured: false}), do: "neutral"
  def completeness_color(%{complete: true}), do: "success"
  def completeness_color(%{chained: true}), do: "information"
  def completeness_color(_commit), do: "neutral"

  @doc false
  def reason_label(%{kind: :no_merge_base, base_branch: branch} = reason),
    do: with_detail(dgettext("dashboard_tests", "the merge base with %{branch} is unknown", branch: branch), reason)

  def reason_label(%{kind: :no_history, commit: ""} = reason),
    do: with_detail(dgettext("dashboard_tests", "the commit is unknown"), reason)

  def reason_label(%{kind: :no_history, commit: sha} = reason),
    do:
      with_detail(
        dgettext("dashboard_tests", "commit %{sha} is not in the repository's Git history", sha: short_sha(sha)),
        reason
      )

  def reason_label(%{kind: :no_measured_commits, base_branch: branch, window_days: days}),
    do:
      dgettext("dashboard_tests", "no measured commit on %{branch} in the last %{days} days", branch: branch, days: days)

  def reason_label(%{kind: :no_ancestor_commit, base_branch: branch, commit: sha, window_commits: commits}),
    do:
      dgettext("dashboard_tests", "no measured commit on %{branch} within %{commits} commits before %{sha}",
        branch: branch,
        commits: commits,
        sha: short_sha(sha)
      )

  def reason_label(%{kind: :measured_set_mismatch, commit: sha, schemes: schemes, baseline_schemes: baseline}),
    do:
      dgettext("dashboard_tests", "commit %{sha} measured %{baseline} where this commit measured %{schemes}",
        sha: short_sha(sha),
        baseline: schemes_label(baseline),
        schemes: schemes_label(schemes)
      )

  def reason_label(%{reason: :partial_run}), do: dgettext("dashboard_tests", "some tests were skipped")
  def reason_label(%{kind: :partial_run}), do: dgettext("dashboard_tests", "some tests were skipped")

  def reason_label(%{reason: :no_history} = reason),
    do: with_detail(dgettext("dashboard_tests", "the run's Git history was not collected"), reason)

  def reason_label(_reason), do: dgettext("dashboard_tests", "unknown")

  defp schemes_label([]), do: dgettext("dashboard_tests", "nothing")
  defp schemes_label(schemes), do: Enum.join(schemes, ", ")

  defp with_detail(text, %{detail: detail}) when is_binary(detail) and detail != "", do: "#{text} (#{detail})"
  defp with_detail(text, _reason), do: text

  @doc "The gates that were evaluated, as the commit page's table lists them."
  def gate_rows(%{checks: checks}), do: Enum.map(checks, &Map.put(&1, :id, Atom.to_string(&1.gate)))

  @doc "The name of a gate, as the settings page and the check run call it."
  def gate_label(:min_patch_coverage), do: dgettext("dashboard_tests", "Minimum patch coverage")
  def gate_label(:max_total_drop), do: dgettext("dashboard_tests", "Maximum total drop")

  @doc """
  What the gates decided for the commit: nothing until its pipeline signals
  completion, since a verdict on a half-measured commit would be wrong.
  """
  def verdict_label(_verdict, false), do: dgettext("dashboard_tests", "Pending")
  def verdict_label(%{conclusion: :success}, _complete), do: dgettext("dashboard_tests", "Passed")
  def verdict_label(%{conclusion: :failure}, _complete), do: dgettext("dashboard_tests", "Failed")
  def verdict_label(_verdict, _complete), do: dgettext("dashboard_tests", "Not decided")

  def verdict_color(_verdict, false), do: "information"
  def verdict_color(%{conclusion: :success}, _complete), do: "success"
  def verdict_color(%{conclusion: :failure}, _complete), do: "destructive"
  def verdict_color(_verdict, _complete), do: "neutral"

  def gate_status_label(:passed), do: dgettext("dashboard_tests", "Passed")
  def gate_status_label(:failed), do: dgettext("dashboard_tests", "Failed")
  def gate_status_label(_status), do: dgettext("dashboard_tests", "Not evaluated")

  def gate_status_color(:passed), do: "success"
  def gate_status_color(:failed), do: "destructive"
  def gate_status_color(_status), do: "neutral"

  @doc "A gate's threshold and what the commit measured against it."
  def gate_threshold(%{gate: :min_patch_coverage, threshold: threshold}),
    do: dgettext("dashboard_tests", "at least %{threshold}%", threshold: threshold)

  def gate_threshold(%{gate: :max_total_drop, threshold: threshold}),
    do: dgettext("dashboard_tests", "at most %{threshold} points down", threshold: threshold)

  def gate_value(%{value: nil}), do: "—"
  def gate_value(%{gate: :min_patch_coverage, value: value}), do: "#{value}%"
  def gate_value(%{gate: :max_total_drop, value: value}), do: "#{signed(value)} pt"

  @doc "The directory a file sits in, or nil for one at the repository's root."
  def parent_dir(path) do
    case Path.dirname(path) do
      "." -> nil
      dir -> dir
    end
  end

  @doc """
  A branch's or pull request's state. Chaining is about a trend, which a
  single head commit has none of, so a ref is either complete or still
  waiting for its pipeline to say so.
  """
  def ref_status_label(%{complete: true}), do: dgettext("dashboard_tests", "Complete")
  def ref_status_label(_ref), do: dgettext("dashboard_tests", "Pending")

  def ref_status_color(%{complete: true}), do: "success"
  def ref_status_color(_ref), do: "information"

  @doc "Whether a ref is a branch or a pull request, as its row's kind reads."
  def ref_kind_label("pull_request"), do: dgettext("dashboard_tests", "Pull request")
  def ref_kind_label(_kind), do: dgettext("dashboard_tests", "Branch")

  def skipped_reason_label(:stale), do: dgettext("dashboard_tests", "Measured on another version of the file")
  def skipped_reason_label(:no_line_data), do: dgettext("dashboard_tests", "No per-line data in the run")
  def skipped_reason_label(:truncated), do: dgettext("dashboard_tests", "Diff too large to record its lines")
  def skipped_reason_label(:not_instrumented), do: dgettext("dashboard_tests", "Not compiled into any tested target")
  def skipped_reason_label(:excluded), do: dgettext("dashboard_tests", "Excluded in the project's coverage settings")

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
