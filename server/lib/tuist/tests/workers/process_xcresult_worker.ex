defmodule Tuist.Tests.Workers.ProcessXcresultWorker do
  @moduledoc """
  Oban worker that parses an uploaded xcresult archive and writes the
  structured test run.

  In the managed deployment the `:process_xcresult` queue only runs on
  external macOS xcresult-processor pods (`TUIST_XCRESULT_PROCESSOR_MODE=true`),
  so this worker's body executes there; the in-cluster Linux server pods
  enqueue jobs but never claim them. In self-hosted installs running on
  macOS the server runs both roles in the same BEAM.

  The xcresult parse path leans on `xcresulttool` from Xcode, which has no
  Linux equivalent — that's why the processor fleet lives outside the
  Hetzner-backed k8s cluster on Scaleway Mac minis.

  The first five attempts download and process the result bundle. Later
  attempts only persist `failed_processing`; when ClickHouse is unavailable,
  that finalization phase snoozes the same Oban job and retries without
  downloading or parsing the bundle again.
  """

  use Oban.Worker,
    queue: :process_xcresult,
    max_attempts: 20,
    unique: [
      keys: [:test_run_id, :shard_index],
      states: [:scheduled, :available, :executing, :retryable],
      period: :infinity
    ]

  alias Tuist.Environment
  alias Tuist.Processor.XCResultProcessor
  alias Tuist.Projects
  alias Tuist.Storage
  alias Tuist.Tests
  alias Tuist.Tests.Workers.BroadcastTestCreatedWorker
  alias Tuist.Tests.XcresultProcessing

  require Logger

  @processing_attempts 5
  @finalization_snooze_seconds 300
  @processing_backoff_seconds {30, 120, 300, 600, 1}

  # Failures whose root cause is the uploaded archive itself, not anything
  # transient. Retrying is pointless and surfacing them as Oban errors lights
  # up Sentry every five attempts for what is fundamentally a CLI-side
  # mistake (xcodebuild never populated the bundle, or the upload was a
  # bare `quarantined_tests.json` skeleton). We mark the run as
  # `failed_processing` once and cancel the job.
  @unprocessable_input_reasons [:bundle_invalid, :xcresult_not_found]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt}) when attempt > @processing_attempts do
    finalize_failed_processing(args)
  end

  def perform(%Oban.Job{args: %{"test_run_id" => test_run_id, "storage_key" => storage_key} = args, attempt: attempt}) do
    case process_xcresult(test_run_id, storage_key, args) do
      {:ok, parsed_data} ->
        case replace_test_run(parsed_data, args) do
          :ok -> complete_processing(args)
          {:error, reason} -> handle_processing_error(args, attempt, reason)
        end

      {:error, reason} when reason in @unprocessable_input_reasons ->
        Logger.info(
          "Cancelling xcresult for test run #{test_run_id}: uploaded archive is unprocessable (#{inspect(reason)})"
        )

        case safely_mark_test_run_failed(args) do
          :ok -> {:cancel, reason}
          {:error, mark_reason} -> {:error, mark_reason}
        end

      {:error, reason} ->
        handle_processing_error(args, attempt, reason)
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) when attempt > 0 and attempt <= tuple_size(@processing_backoff_seconds) do
    elem(@processing_backoff_seconds, attempt - 1)
  end

  def backoff(job), do: Oban.Worker.backoff(job)

  defp complete_processing(args) do
    # The run just finished on this (isolated, non-clustered) processor
    # node, so the in-process PubSub broadcast from create_test can't
    # reach the web tier. Enqueue an explicit notify job that a web pod
    # will pick up and broadcast from inside the cluster.
    enqueue_test_run_broadcast(args)

    case Map.get(args, "vcs_comment_params", %{}) do
      params when params != %{} -> Tuist.VCS.enqueue_vcs_pull_request_comment(params)
      _ -> :ok
    end

    :ok
  end

  defp handle_processing_error(args, @processing_attempts, reason) do
    Logger.error(
      "Failed to process xcresult for test run #{args["test_run_id"]} after #{@processing_attempts} attempts: #{inspect(reason)}"
    )

    {:error, reason}
  end

  defp handle_processing_error(_args, _attempt, reason), do: {:error, reason}

  defp finalize_failed_processing(args) do
    with :ok <- safely_mark_test_run_failed(args),
         {:ok, _job} <- safely_enqueue_test_run_broadcast(args) do
      {:cancel, :processing_failed}
    else
      {:error, reason} ->
        Logger.error("Failed to finalize Xcode result processing for test run #{args["test_run_id"]}: #{inspect(reason)}")

        {:snooze, @finalization_snooze_seconds}
    end
  end

  defp safely_enqueue_test_run_broadcast(args) do
    enqueue_test_run_broadcast(args)
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp safely_mark_test_run_failed(args) do
    XcresultProcessing.mark_test_run_failed(args)
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp enqueue_test_run_broadcast(args) do
    %{test_run_id: args["test_run_id"], project_id: args["project_id"]}
    |> BroadcastTestCreatedWorker.new()
    |> Oban.insert()
  end

  # Storage routes per account, so the download backend must be the project's
  # account (where the xcresult was uploaded and the key is namespaced), not
  # the run's `account_id`, which records who ran the tests and can be a member
  # with a different personal account.
  defp process_xcresult(test_run_id, storage_key, args) do
    with {:ok, account} <- storage_account(args["project_id"]) do
      # For sharded runs, multiple workers share the same merged
      # test_run_id and can run concurrently. Suffix the temp path with
      # the shard index so they never clobber each other's download
      # mid-parse. Oban's unique job configuration already keeps a given
      # (test_run_id, shard_index) pair from running in parallel.
      filename =
        case Map.get(args, "shard_index") do
          nil -> "xcresult_#{test_run_id}.zip"
          index -> "xcresult_#{test_run_id}_s#{index}.zip"
        end

      temp_path = Path.join(System.tmp_dir!(), filename)

      try do
        case Storage.download_to_file(storage_key, temp_path, account) do
          {:ok, _} ->
            opts = [
              test_run_id: test_run_id,
              account_handle: args["account_handle"],
              project_handle: args["project_handle"],
              s3_bucket: Environment.s3_bucket_name()
            ]

            XCResultProcessor.process_local(temp_path, opts)

          {:error, _} = error ->
            error
        end
      after
        File.rm(temp_path)
      end
    end
  end

  defp storage_account(project_id) do
    case Projects.get_project_by_id(project_id) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project.account}
    end
  end

  defp replace_test_run(parsed_data, args) do
    test_modules = parsed_data["test_modules"] || []

    attrs =
      Map.merge(XcresultProcessing.base_test_attrs(args), %{
        scheme: parsed_data["test_plan_name"] || Map.get(args, "scheme"),
        status: run_status(parsed_data, test_modules),
        duration: parsed_data["duration"] || 0,
        test_modules: test_modules,
        run_destinations: normalize_run_destinations(parsed_data["run_destinations"] || []),
        run_errors: parsed_data["errors"] || []
      })

    case Tests.create_test(attrs) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # A parse that extracted no test modules found nothing usable in the bundle
  # (an aborted or empty xcresult). The Swift parser reports that as "skipped"
  # — vacuously, from an empty test-case list — which reads on the dashboard as
  # a real skip rather than "we couldn't parse this". Surface it as
  # failed_processing so it isn't mistaken for a passing or skipped run.
  defp run_status(_parsed_data, []), do: "failed_processing"
  defp run_status(parsed_data, _test_modules), do: parsed_data["status"] || "success"

  # The xcresult `platform` field uses display strings ("iOS Simulator",
  # "macOS"). We persist the snake-case form in `test_run_destinations` so
  # ClickHouse holds the canonical value directly. iPadOS folds onto the
  # iOS family — the icon set has no separate iPad glyph and Xcode's own
  # xcresult viewer treats iPad sims as iOS Simulator anyway.
  defp normalize_run_destinations(destinations) do
    Enum.map(destinations, fn destination ->
      %{
        name: destination["name"],
        platform: normalize_platform(destination["platform"]),
        os_version: destination["os_version"]
      }
    end)
  end

  defp normalize_platform("macOS"), do: "macos"
  defp normalize_platform("iOS"), do: "ios"
  defp normalize_platform("iOS Simulator"), do: "ios_simulator"
  defp normalize_platform("iPadOS"), do: "ios"
  defp normalize_platform("iPadOS Simulator"), do: "ios_simulator"
  defp normalize_platform("tvOS"), do: "tvos"
  defp normalize_platform("tvOS Simulator"), do: "tvos_simulator"
  defp normalize_platform("watchOS"), do: "watchos"
  defp normalize_platform("watchOS Simulator"), do: "watchos_simulator"
  defp normalize_platform("visionOS"), do: "visionos"
  defp normalize_platform("visionOS Simulator"), do: "visionos_simulator"
  defp normalize_platform(_), do: "unknown"
end
