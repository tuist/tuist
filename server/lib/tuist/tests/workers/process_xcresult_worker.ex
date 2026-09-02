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
      states: :incomplete,
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
  require OpenTelemetry.Tracer

  @processing_attempts 5
  @finalization_snooze_seconds 300
  @processing_backoff_seconds {30, 120, 300, 600, 1}

  # Failures whose root cause is the uploaded archive itself, not anything
  # transient. Retrying is pointless and surfacing them as Oban errors lights
  # up Sentry every five attempts for what is fundamentally a CLI-side
  # mistake (xcodebuild never populated the bundle, the upload was a bare
  # `quarantined_tests.json` skeleton, or `xcresulttool` reads the bundle and
  # returns no test results at all). We mark the run as `failed_processing`
  # once and cancel the job.
  @unprocessable_input_reasons [:bundle_invalid, :xcresult_not_found, :empty_test_results]

  # A parse timeout is the one failure that costs a worker slot the full
  # NIF deadline (10 minutes) before it reports anything, so it is also the
  # one where the default five processing attempts are actively harmful.
  #
  # The parse is CPU-bound and the fleet is small (one VM per Mac mini, one
  # in-flight parse per performance core), so replaying a bundle that just
  # blew the deadline puts the same work back on the same saturated cores.
  # Every replay is 10 more minutes that a parse which *would* have finished
  # does not get, which pushes borderline bundles over the deadline, which
  # enqueues more replays: the queue collapses to near-zero goodput while
  # every tenant's parse times out. That is exactly what the 2026-08-29
  # incident looked like — whatnot, pinterest and vinted all timing out
  # together, jobs still on attempt 2 four hours after the run was uploaded.
  #
  # One retry is kept rather than none: a bundle can cross the deadline
  # purely because the fleet was busy when it ran, and a second pass does
  # succeed once the queue drains. Beyond that the honest answer is that we
  # cannot parse this bundle in the budget we have, so mark the run
  # `failed_processing` and cancel instead of burning four more slots on it.
  @parse_timeout_attempts 2
  @parse_timeout_backoff_seconds 900

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"test_run_id" => test_run_id}} = job) do
    OpenTelemetry.Tracer.with_span "xcresult.process" do
      OpenTelemetry.Tracer.set_attribute("test_run_id", test_run_id)
      perform_job(job)
    end
  end

  defp perform_job(%Oban.Job{args: args, attempt: attempt}) when attempt > @processing_attempts do
    finalize_failed_processing(args)
  end

  defp perform_job(%Oban.Job{
         args: %{"test_run_id" => test_run_id, "storage_key" => storage_key} = args,
         attempt: attempt
       }) do
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

        cancel_as_failed(args, reason)

      {:error, :parse_timeout = reason} when attempt >= @parse_timeout_attempts ->
        Logger.error(
          "Cancelling xcresult for test run #{test_run_id}: parsing exceeded its timeout on #{attempt} attempts"
        )

        cancel_as_failed(args, reason)

      {:error, reason} ->
        handle_processing_error(args, attempt, reason)
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{errors: errors} = job) do
    if parse_timeout?(errors) do
      @parse_timeout_backoff_seconds
    else
      processing_backoff(job)
    end
  end

  defp processing_backoff(%Oban.Job{attempt: attempt})
       when attempt > 0 and attempt <= tuple_size(@processing_backoff_seconds) do
    elem(@processing_backoff_seconds, attempt - 1)
  end

  defp processing_backoff(job), do: Oban.Worker.backoff(job)

  # The transient-error ladder above starts at 30 seconds, which is the wrong
  # shape for the one retry a parse timeout gets: the job has already spent
  # the full deadline on a busy fleet, and coming back half a minute later
  # re-runs the same work against the same busy cores. Wait out the in-flight
  # parses it would otherwise compete with instead.
  #
  # Oban only exposes the previous failures as formatted strings, so this
  # sniffs the reason out of the last one. A change in Oban's formatting
  # costs us the longer wait and falls back to the ladder, which is what this
  # path does today, so the retry cap never depends on the match.
  defp parse_timeout?(errors) when is_list(errors) do
    case List.last(errors) do
      %{"error" => error} when is_binary(error) -> String.contains?(error, "parse_timeout")
      _ -> false
    end
  end

  defp parse_timeout?(_errors), do: false

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

  # Record the run as `failed_processing` and stop replaying the job. Cancel
  # rather than error so the failure doesn't keep consuming attempts (and
  # Sentry events) for something a replay cannot change; if marking the run
  # fails we still return an error so the job retries and the run doesn't
  # get stranded mid-processing.
  defp cancel_as_failed(args, reason) do
    case safely_mark_test_run_failed(args) do
      :ok -> {:cancel, reason}
      {:error, mark_reason} -> {:error, mark_reason}
    end
  end

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
        download =
          OpenTelemetry.Tracer.with_span "xcresult.download" do
            Storage.download_to_file(storage_key, temp_path, account)
          end

        case download do
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

  # Sibling of the parse spans in `XCResultProcessor`: this is the ClickHouse
  # write half of the job, and splitting it out is what makes it possible to
  # say whether a slow job was slow at parsing or at persisting.
  defp replace_test_run(parsed_data, args) do
    OpenTelemetry.Tracer.with_span "xcresult.persist" do
      do_replace_test_run(parsed_data, args)
    end
  end

  defp do_replace_test_run(parsed_data, args) do
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

  # A runner error empties the module list without the run having passed: a target
  # whose `.xctest` cannot be loaded, or a UI-test runner that cannot launch, is
  # lifted out of the test cases by the parser, so it arrives with no modules and
  # `status: "failure"`. That verdict is the parser's, and it stands. Keyed on the
  # status rather than on `errors` being non-empty, because `errors` also carries
  # unattributed issues, which deliberately leave the status alone.
  defp run_status(%{"status" => "failure"}, []), do: "failure"

  # Otherwise no test modules means xcodebuild finished without running anything:
  # the selection resolved to zero tests. Xcode reports that as a passing run with
  # `totalTestCount: 0` and no issues, so this mirrors it. The Swift parser's own
  # status would be "skipped", derived vacuously from an empty test-case list,
  # which reads as a deliberate skip instead.
  defp run_status(_parsed_data, []), do: "success"
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
