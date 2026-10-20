defmodule TuistWeb.OnceTestCaseRunLive do
  @moduledoc """
  Detail page for a single Once test case attempt. Mirrors
  `TuistWeb.TestCaseRunLive` markup — same container id and
  `data-part`s — so `pages/test_case_run.css` styles it identically.
  """
  use TuistWeb, :live_view
  use Noora

  import Ecto.Query
  import TuistWeb.Components.EmptyCardSection

  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Run
  alias Tuist.OnceEvents.TestCaseRun
  alias Tuist.Repo
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError

  def mount(
        %{"once_run_id" => run_id, "case_id" => case_id},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    run =
      Repo.one(from(r in Run, where: r.project_id == ^project.id and r.run_id == ^run_id))

    if is_nil(run) do
      raise NotFoundError,
            "Could not find Once test run #{inspect(run_id)}"
    end

    test_case =
      Repo.one(from(c in TestCaseRun, where: c.once_run_id == ^run.id and c.id == ^case_id))

    if is_nil(test_case) do
      raise NotFoundError,
            "Could not find Once test case #{inspect(case_id)}"
    end

    if connected?(socket) do
      OnceEvents.subscribe_run(run.project_id, run.run_id)
    end

    {:ok,
     socket
     |> assign(
       :head_title,
       "#{test_case.name} · #{account.name}/#{project.name} · Tuist"
     )
     |> assign(:run, run)
     |> assign(:test_case, test_case)}
  end

  def handle_params(_params, uri, socket) do
    parsed_uri = URI.parse(uri)

    selected_tab =
      case parsed_uri.query do
        nil -> "overview"
        query -> URI.decode_query(query)["tab"] || "overview"
      end

    {:noreply,
     socket
     |> assign(:uri, parsed_uri)
     |> assign(:selected_tab, selected_tab)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---- Presentation helpers -------------------------------------------

  def status_class(%TestCaseRun{result: "passed"}), do: "success"
  def status_class(%TestCaseRun{result: "failed"}), do: "failure"
  def status_class(%TestCaseRun{result: "skipped"}), do: "skipped"
  def status_class(_), do: "in_progress"

  def status_label(%TestCaseRun{result: "passed"}), do: dgettext("dashboard_tests", "Passed")
  def status_label(%TestCaseRun{result: "failed"}), do: dgettext("dashboard_tests", "Failed")
  def status_label(%TestCaseRun{result: "skipped"}), do: dgettext("dashboard_tests", "Skipped")
  def status_label(%TestCaseRun{result: other}), do: String.capitalize(other || "unknown")

  def format_duration(nil), do: "—"
  def format_duration(ms), do: DateFormatter.format_duration_from_milliseconds(ms)

  def format_datetime(nil, _tz), do: "—"

  def format_datetime(%NaiveDateTime{} = ndt, tz) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateFormatter.format_with_timezone(tz || "Etc/UTC")
  end

  def format_datetime(%DateTime{} = dt, tz), do: DateFormatter.format_with_timezone(dt, tz || "Etc/UTC")

  def test_run_path(assigns, run) do
    ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/once/test-runs/#{run.run_id}"
  end
end
