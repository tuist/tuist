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
  """

  use Oban.Worker, queue: :process_xcresult, max_attempts: 5, unique: [keys: [:test_run_id]]

  alias Tuist.Accounts
  alias Tuist.Storage
  alias Tuist.Tests

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"test_run_id" => test_run_id, "storage_key" => storage_key, "account_id" => account_id} = args,
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    case process_xcresult(test_run_id, storage_key, account_id, args) do
      {:ok, parsed_data} ->
        replace_test_run(parsed_data, args)

        case Map.get(args, "vcs_comment_params", %{}) do
          params when params != %{} -> Tuist.VCS.enqueue_vcs_pull_request_comment(params)
          _ -> :ok
        end

        :ok

      {:error, reason} ->
        if attempt >= max_attempts do
          Logger.error(
            "Failed to process xcresult for test run #{test_run_id} after #{max_attempts} attempts: #{inspect(reason)}"
          )

          mark_failed_processing(args)
        end

        {:error, reason}
    end
  end

  defp process_xcresult(test_run_id, storage_key, account_id, args) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id) do
      temp_path = Path.join(System.tmp_dir!(), "xcresult_#{test_run_id}.zip")

      try do
        case Storage.download_to_file(storage_key, temp_path, account) do
          {:ok, _} ->
            opts = [
              test_run_id: test_run_id,
              account_handle: args["account_handle"],
              project_handle: args["project_handle"],
              s3_bucket: Tuist.Environment.s3_bucket_name()
            ]

            Tuist.Processor.XCResultProcessor.process_local(temp_path, opts)

          {:error, _} = error ->
            error
        end
      after
        File.rm(temp_path)
      end
    end
  end

  defp replace_test_run(parsed_data, args) do
    attrs =
      Map.merge(base_attrs(args), %{
        scheme: parsed_data["test_plan_name"] || Map.get(args, "scheme"),
        status: parsed_data["status"] || "success",
        duration: parsed_data["duration"] || 0,
        test_modules: parsed_data["test_modules"] || [],
        run_destinations: normalize_run_destinations(parsed_data["run_destinations"] || [])
      })

    case Tests.create_test(attrs) do
      {:ok, _} -> :ok
      error -> error
    end
  end

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

  defp mark_failed_processing(args) do
    attrs =
      Map.merge(base_attrs(args), %{
        status: "failed_processing",
        duration: 0,
        test_modules: []
      })

    case Tests.create_test(attrs) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp base_attrs(args) do
    %{
      id: args["test_run_id"],
      project_id: args["project_id"],
      account_id: args["account_id"],
      is_ci: Map.get(args, "is_ci", false),
      git_branch: Map.get(args, "git_branch"),
      git_commit_sha: Map.get(args, "git_commit_sha"),
      git_ref: Map.get(args, "git_ref"),
      macos_version: Map.get(args, "macos_version"),
      xcode_version: Map.get(args, "xcode_version"),
      model_identifier: Map.get(args, "model_identifier"),
      scheme: Map.get(args, "scheme"),
      ci_run_id: Map.get(args, "ci_run_id"),
      ci_project_handle: Map.get(args, "ci_project_handle"),
      ci_host: Map.get(args, "ci_host"),
      ci_provider: Map.get(args, "ci_provider"),
      build_run_id: Map.get(args, "build_run_id"),
      shard_plan_id: Map.get(args, "shard_plan_id"),
      shard_index: Map.get(args, "shard_index"),
      ran_at: NaiveDateTime.utc_now()
    }
  end
end
