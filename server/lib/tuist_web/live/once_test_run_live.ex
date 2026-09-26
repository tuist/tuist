defmodule TuistWeb.OnceTestRunLive do
  @moduledoc """
  Detail page for a Once test run. Mirrors `TuistWeb.TestRunLive` markup
  — same container id, same `data-part` values — so `test_run.css`
  styles it identically. Data comes from `once_runs`,
  `once_test_case_runs`, and `once_test_suite_runs`.
  """
  use TuistWeb, :live_view
  use Noora

  import Ecto.Query
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Helpers.VCSLinks

  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Run
  alias Tuist.OnceEvents.TestCaseRun
  alias Tuist.OnceEvents.TestSuiteRun
  alias Tuist.Repo
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Utilities.Query

  @page_size 20

  # A run broadcasts once per ingested test case, so a suite of a few
  # thousand tests would otherwise re-run both table queries a few
  # thousand times while it streams in. Notifications instead set a flag
  # and one refresh is scheduled per window.
  @refresh_interval_ms 1_000

  def mount(
        %{"once_run_id" => run_id},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    case load_run(project.id, run_id) do
      nil ->
        raise TuistWeb.Errors.NotFoundError,
              "Could not find Once test run #{inspect(run_id)}"

      run ->
        if connected?(socket) do
          OnceEvents.subscribe_run(run.project_id, run.run_id)
        end

        socket =
          socket
          |> assign(
            :head_title,
            "#{display_label(run)} · #{account.name}/#{project.name} · Tuist"
          )
          |> assign(:run, run)
          |> assign(:test_metrics, compute_metrics(run))
          |> assign(:refresh_scheduled?, false)

        {:ok, socket}
    end
  end

  def handle_params(params, uri, socket) do
    parsed_uri = URI.parse(uri)
    selected_tab = params["tab"] || "test-cases"
    test_cases_page = page_param(params["test-cases-page"])
    test_suites_page = page_param(params["test-targets-page"])

    {:noreply,
     socket
     |> assign(:uri, parsed_uri)
     |> assign(:selected_tab, selected_tab)
     |> assign(:test_cases_page, test_cases_page)
     |> assign(:test_suites_page, test_suites_page)
     |> load_tables()}
  end

  def handle_info({:test_case_ingested, _run_id}, socket), do: schedule_refresh(socket)
  def handle_info({:test_suite_ingested, _run_id}, socket), do: schedule_refresh(socket)
  def handle_info({:run_updated, _run_id}, socket), do: schedule_refresh(socket)
  def handle_info(:refresh, socket), do: refresh(socket)
  def handle_info(_, socket), do: {:noreply, socket}

  defp schedule_refresh(%{assigns: %{refresh_scheduled?: true}} = socket), do: {:noreply, socket}

  defp schedule_refresh(socket) do
    Process.send_after(self(), :refresh, @refresh_interval_ms)
    {:noreply, assign(socket, :refresh_scheduled?, true)}
  end

  defp refresh(%{assigns: %{run: run, selected_project: project}} = socket) do
    run = load_run(project.id, run.run_id) || run

    {:noreply,
     socket
     |> assign(:run, run)
     |> assign(:test_metrics, compute_metrics(run))
     |> assign(:refresh_scheduled?, false)
     |> load_tables()}
  end

  defp load_tables(%{assigns: %{run: run, test_cases_page: cases_page, test_suites_page: suites_page}} = socket) do
    socket
    |> assign_async(:test_cases, fn -> {:ok, %{test_cases: load_test_cases(run.id, cases_page)}} end)
    |> assign(:test_cases_total_pages, total_pages(count_test_cases(run.id)))
    |> assign_async(:test_suites, fn -> {:ok, %{test_suites: load_test_suites(run.id, suites_page)}} end)
    |> assign(:test_suites_total_pages, total_pages(count_test_suites(run.id)))
  end

  defp page_param(value) do
    case value && Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp total_pages(count), do: max(1, ceil(count / @page_size))

  def page_patch(uri, param) do
    fn page -> "?" <> Query.put(uri.query, param, page) end
  end

  # ---- Presentation helpers used by the template ----------------------

  def status(%{exit_status: 0}), do: "success"

  def status(%{exit_status: nil, finalization: finalization}) do
    if finalization == "finalized", do: "success", else: "in_progress"
  end

  def status(_), do: "failure"

  def display_label(%Run{command_display: cmd}) when is_binary(cmd) and cmd != "", do: cmd
  def display_label(%Run{run_id: run_id}), do: run_id

  def test_runs_list_path(assigns) do
    ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/once/test-runs"
  end

  def test_case_run_path(assigns, run, test_case) do
    ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/once/test-runs/#{run.run_id}/test-cases/#{test_case.id}"
  end

  def format_duration(nil), do: "—"
  def format_duration(ms), do: DateFormatter.format_duration_from_milliseconds(ms)

  def format_datetime(nil, _tz), do: "—"

  def format_datetime(%DateTime{} = dt, tz), do: DateFormatter.format_with_timezone(dt, tz || "Etc/UTC")

  # ---- Internals -------------------------------------------------------

  defp load_run(project_id, run_id) do
    Repo.one(
      from(r in Run,
        where: r.project_id == ^project_id and r.run_id == ^run_id,
        limit: 1
      )
    )
  end

  # A single run can report tens of thousands of cases, so the table is
  # paged. Failures sort first so the first page is the one worth reading
  # when a run is large.
  defp load_test_cases(once_run_id, page) do
    Repo.all(
      from(c in TestCaseRun,
        where: c.once_run_id == ^once_run_id,
        order_by: [asc: fragment("? = 'passed'", c.result), asc: c.name, asc: c.attempt],
        limit: ^@page_size,
        offset: ^((page - 1) * @page_size)
      )
    )
  end

  defp count_test_cases(once_run_id) do
    Repo.aggregate(from(c in TestCaseRun, where: c.once_run_id == ^once_run_id), :count, :id)
  end

  defp load_test_suites(once_run_id, page) do
    Repo.all(
      from(s in TestSuiteRun,
        where: s.once_run_id == ^once_run_id,
        order_by: [asc: s.suite_id],
        limit: ^@page_size,
        offset: ^((page - 1) * @page_size)
      )
    )
  end

  defp count_test_suites(once_run_id) do
    Repo.aggregate(from(s in TestSuiteRun, where: s.once_run_id == ^once_run_id), :count, :id)
  end

  defp compute_metrics(run) do
    total = run.test_case_count || 0
    passed = run.passed_test_cases || 0
    failed = run.failed_test_cases || 0

    avg =
      cond do
        total <= 0 -> 0
        run.wall_ms in [nil, 0] -> 0
        true -> div(run.wall_ms, max(total, 1))
      end

    %{
      total_count: total,
      passed_count: passed,
      failed_count: failed,
      flaky_count: 0,
      avg_duration: avg,
      suite_count: run.test_suite_count || 0
    }
  end
end
