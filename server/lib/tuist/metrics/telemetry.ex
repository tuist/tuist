defmodule Tuist.Metrics.Telemetry do
  @moduledoc """
  Attaches telemetry handlers that feed the per-account metrics aggregator.

  The user-facing scrape metrics use the `[:tuist, :metrics, ...]` event prefix
  so they are easy to distinguish from internal operational telemetry — the
  RFC commenters asked for a naming convention that separates the two.

  Non-scrape events that already exist in the system (CLI run commands, cache
  events) are bridged into the aggregator here rather than renaming the
  existing event tree.
  """

  require Logger

  alias Tuist.Metrics

  @handler_id "tuist-metrics-aggregator"

  @events [
    # Bridged from existing telemetry events
    [:tuist, :run, :command],
    [:tuist, :cache, :event],
    # User-facing metrics events emitted where builds/tests are recorded
    [:tuist, :metrics, :xcode, :build, :run],
    [:tuist, :metrics, :xcode, :test, :run],
    [:tuist, :metrics, :xcode, :test, :case],
    [:tuist, :metrics, :gradle, :build, :run],
    [:tuist, :metrics, :gradle, :test, :run]
  ]

  def attach do
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil)
  end

  def detach do
    :telemetry.detach(@handler_id)
  end

  @doc false
  def handle_event(event, measurements, metadata, _config) do
    handle(event, measurements, metadata)
  rescue
    exception ->
      # A metrics handler must never take down the process that emitted the
      # event. Log and swallow so the main code path is unaffected.
      Logger.warning(
        "Tuist.Metrics.Telemetry handler crashed for #{inspect(event)}: #{Exception.message(exception)}"
      )
  end

  # ---- CLI ---------------------------------------------------------------

  defp handle([:tuist, :run, :command], %{duration: duration_ms}, %{command_event: event}) do
    with %{account_id: account_id} = labels <- cli_labels(event) do
      labels = Map.delete(labels, :account_id)

      Metrics.increment_counter(account_id, "tuist_cli_invocations_total", labels)

      Metrics.observe_histogram(
        account_id,
        "tuist_cli_invocation_duration_seconds",
        labels,
        ms_to_seconds(duration_ms)
      )
    end
  end

  # ---- Cache events ------------------------------------------------------

  defp handle([:tuist, :cache, :event], %{count: count}, %{event_type: event_type} = meta)
       when is_integer(count) and count > 0 do
    with %{account_id: account_id, project: project} <- cache_labels(meta) do
      Metrics.increment_counter(
        account_id,
        "tuist_xcode_cache_events_total",
        %{project: project, event_type: to_string(event_type)},
        count
      )
    end
  end

  defp handle([:tuist, :cache, :event], _measurements, _metadata), do: :ok

  # ---- Xcode build/test --------------------------------------------------

  defp handle(
         [:tuist, :metrics, :xcode, :build, :run],
         %{duration_seconds: duration},
         %{account_id: account_id} = meta
       ) do
    labels = xcode_build_labels(meta)
    Metrics.increment_counter(account_id, "tuist_xcode_build_runs_total", labels)

    Metrics.observe_histogram(
      account_id,
      "tuist_xcode_build_run_duration_seconds",
      labels,
      duration
    )
  end

  defp handle(
         [:tuist, :metrics, :xcode, :test, :run],
         %{duration_seconds: duration},
         %{account_id: account_id} = meta
       ) do
    labels = xcode_test_labels(meta)
    Metrics.increment_counter(account_id, "tuist_xcode_test_runs_total", labels)

    Metrics.observe_histogram(
      account_id,
      "tuist_xcode_test_run_duration_seconds",
      labels,
      duration
    )
  end

  defp handle(
         [:tuist, :metrics, :xcode, :test, :case],
         %{count: count},
         %{account_id: account_id} = meta
       )
       when is_integer(count) and count > 0 do
    labels = %{
      project: meta[:project] || "",
      scheme: meta[:scheme] || "",
      is_ci: to_string(meta[:is_ci] || false),
      status: to_string(meta[:status] || "")
    }

    Metrics.increment_counter(account_id, "tuist_xcode_test_cases_total", labels, count)
  end

  # ---- Gradle build/test -------------------------------------------------

  defp handle(
         [:tuist, :metrics, :gradle, :build, :run],
         %{duration_seconds: duration},
         %{account_id: account_id} = meta
       ) do
    labels = gradle_labels(meta)
    Metrics.increment_counter(account_id, "tuist_gradle_build_runs_total", labels)

    Metrics.observe_histogram(
      account_id,
      "tuist_gradle_build_run_duration_seconds",
      labels,
      duration
    )
  end

  defp handle(
         [:tuist, :metrics, :gradle, :test, :run],
         %{duration_seconds: duration},
         %{account_id: account_id} = meta
       ) do
    labels = gradle_labels(meta)
    Metrics.increment_counter(account_id, "tuist_gradle_test_runs_total", labels)

    Metrics.observe_histogram(
      account_id,
      "tuist_gradle_test_run_duration_seconds",
      labels,
      duration
    )
  end

  defp handle(_event, _measurements, _metadata), do: :ok

  # ---- Label helpers -----------------------------------------------------

  defp cli_labels(%{project_id: nil}), do: nil

  defp cli_labels(%{project_id: project_id} = event) do
    case lookup_project(project_id) do
      nil ->
        nil

      %{account_id: account_id, project_handle: handle} ->
        %{
          account_id: account_id,
          project: handle,
          command: event_string(event, :name),
          is_ci: to_string(!!event_get(event, :is_ci)),
          status: command_status(event)
        }
    end
  end

  defp cli_labels(_), do: nil

  defp cache_labels(%{project_id: project_id}) do
    with project_id when not is_nil(project_id) <- project_id,
         %{account_id: account_id, project_handle: handle} <- lookup_project(project_id) do
      %{account_id: account_id, project: handle}
    else
      _ -> nil
    end
  end

  defp cache_labels(_), do: nil

  defp xcode_build_labels(meta) do
    %{
      project: meta[:project] || "",
      scheme: meta[:scheme] || "",
      is_ci: to_string(meta[:is_ci] || false),
      status: to_string(meta[:status] || ""),
      xcode_version: meta[:xcode_version] || "",
      macos_version: meta[:macos_version] || ""
    }
  end

  defp xcode_test_labels(meta), do: xcode_build_labels(meta)

  defp gradle_labels(meta) do
    %{
      project: meta[:project] || "",
      module: meta[:module] || "",
      is_ci: to_string(meta[:is_ci] || false),
      status: to_string(meta[:status] || ""),
      gradle_version: meta[:gradle_version] || "",
      jvm_version: meta[:jvm_version] || ""
    }
  end

  # ---- Utility -----------------------------------------------------------

  defp ms_to_seconds(ms) when is_integer(ms), do: ms / 1_000
  defp ms_to_seconds(ms) when is_float(ms), do: ms / 1_000
  defp ms_to_seconds(_), do: 0

  defp command_status(event) do
    if Map.get(event, :status) == :success or event_get(event, :error_message) in [nil, ""] do
      "success"
    else
      "failure"
    end
  end

  defp event_get(event, key) when is_map(event), do: Map.get(event, key)
  defp event_get(_, _), do: nil

  defp event_string(event, key) do
    case event_get(event, key) do
      nil -> ""
      value when is_binary(value) -> value
      other -> to_string(other)
    end
  end

  defp lookup_project(project_id) do
    case Tuist.Projects.get_project_by_id(project_id) do
      %{account: %{name: account_handle, id: account_id}} = project ->
        %{
          account_id: account_id,
          project_handle: "#{account_handle}/#{project.name}"
        }

      _ ->
        nil
    end
  end

  @doc "Telemetry event name for Xcode build-run observations."
  def event_name_xcode_build_run, do: [:tuist, :metrics, :xcode, :build, :run]

  @doc "Telemetry event name for Xcode test-run observations."
  def event_name_xcode_test_run, do: [:tuist, :metrics, :xcode, :test, :run]

  @doc "Telemetry event name for Xcode test case aggregate observations."
  def event_name_xcode_test_case, do: [:tuist, :metrics, :xcode, :test, :case]

  @doc "Telemetry event name for Gradle build-run observations."
  def event_name_gradle_build_run, do: [:tuist, :metrics, :gradle, :build, :run]

  @doc "Telemetry event name for Gradle test-run observations."
  def event_name_gradle_test_run, do: [:tuist, :metrics, :gradle, :test, :run]
end
