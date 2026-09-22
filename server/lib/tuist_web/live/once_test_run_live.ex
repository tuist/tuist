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
          OnceEvents.subscribe_run(run.run_id)
        end

        socket =
          socket
          |> assign(
            :head_title,
            "#{display_label(run)} · #{account.name}/#{project.name} · Tuist"
          )
          |> assign(:run, run)
          |> assign(:test_metrics, compute_metrics(run))
          |> assign_async(:test_cases, fn -> {:ok, %{test_cases: load_test_cases(run.id)}} end)
          |> assign_async(:test_suites, fn -> {:ok, %{test_suites: load_test_suites(run.id)}} end)

        {:ok, socket}
    end
  end

  def handle_params(_params, uri, socket) do
    parsed_uri = URI.parse(uri)

    selected_tab =
      case parsed_uri.query do
        nil -> "test-cases"
        query -> URI.decode_query(query)["tab"] || "test-cases"
      end

    {:noreply,
     socket
     |> assign(:uri, parsed_uri)
     |> assign(:selected_tab, selected_tab)}
  end

  def handle_info({:test_case_ingested, _run_id}, socket), do: refresh(socket)
  def handle_info({:test_suite_ingested, _run_id}, socket), do: refresh(socket)
  def handle_info({:run_updated, _run_id}, socket), do: refresh(socket)
  def handle_info(_, socket), do: {:noreply, socket}

  defp refresh(%{assigns: %{run: run, selected_project: project}} = socket) do
    run = load_run(project.id, run.run_id) || run

    {:noreply,
     socket
     |> assign(:run, run)
     |> assign(:test_metrics, compute_metrics(run))
     |> assign_async(:test_cases, fn -> {:ok, %{test_cases: load_test_cases(run.id)}} end)
     |> assign_async(:test_suites, fn -> {:ok, %{test_suites: load_test_suites(run.id)}} end)}
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

  def format_datetime(%DateTime{} = dt, tz),
    do: DateFormatter.format_with_timezone(dt, tz || "Etc/UTC")

  # ---- Internals -------------------------------------------------------

  defp load_run(project_id, run_id) do
    Repo.one(
      from(r in Run,
        where: r.project_id == ^project_id and r.run_id == ^run_id,
        limit: 1
      )
    )
  end

  defp load_test_cases(once_run_id) do
    from(c in TestCaseRun,
      where: c.once_run_id == ^once_run_id,
      order_by: [asc: c.name]
    )
    |> Repo.all()
  end

  defp load_test_suites(once_run_id) do
    from(s in TestSuiteRun,
      where: s.once_run_id == ^once_run_id,
      order_by: [asc: s.suite_id]
    )
    |> Repo.all()
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
