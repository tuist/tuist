defmodule Tuist.Builds.Workers.ProcessBuildWorker do
  @moduledoc """
  Oban worker that parses an uploaded xcactivitylog archive and writes the
  structured build run.

  In the managed deployment the `:process_build` queue only runs on processor
  pods (`TUIST_PROCESSOR_MODE=true`), so this worker's body executes there;
  the server pods enqueue jobs but never claim them. In self-hosted installs
  the server runs both roles in the same BEAM.
  """

  use Oban.Worker, queue: :process_build, max_attempts: 5

  alias Tuist.Accounts
  alias Tuist.Builds
  alias Tuist.Storage

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{"build_id" => build_id, "storage_key" => storage_key, "account_id" => account_id, "project_id" => project_id} =
            args,
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    xcode_cache_upload_enabled = Map.get(args, "xcode_cache_upload_enabled", false)
    build_metadata = Map.get(args, "build_metadata", %{})

    case process_build(build_id, storage_key, account_id, xcode_cache_upload_enabled) do
      {:ok, parsed_data} ->
        parsed_data = Map.put(parsed_data, "project_id", project_id)
        replace_build_run(build_id, parsed_data, account_id, build_metadata)

        case Map.get(args, "vcs_comment_params", %{}) do
          params when params != %{} -> Tuist.VCS.enqueue_vcs_pull_request_comment(params)
          _ -> :ok
        end

      {:error, reason} ->
        if attempt >= max_attempts do
          Logger.error("Build processing failed permanently for build #{build_id}: #{inspect(reason)}")
          mark_failed_build_processing(build_id, project_id, account_id, build_metadata)
        end

        {:error, reason}
    end
  end

  defp process_build(build_id, storage_key, account_id, xcode_cache_upload_enabled) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id) do
      temp_path = Path.join(System.tmp_dir!(), "build_#{build_id}.zip")

      try do
        case Storage.download_to_file(storage_key, temp_path, account) do
          {:ok, _} ->
            Tuist.Processor.BuildProcessor.process_build(temp_path, xcode_cache_upload_enabled)

          {:error, _} = error ->
            error
        end
      after
        File.rm(temp_path)
      end
    end
  end

  defp replace_build_run(build_id, parsed_data, account_id, build_metadata) do
    parsed = atomize_keys(parsed_data)

    attrs =
      Map.merge(base_build_attrs(build_id, account_id, build_metadata), %{
        project_id: parsed[:project_id],
        duration: parsed[:duration] || 0,
        status: parsed[:status] || "success",
        category: parsed[:category],
        targets: Enum.map(parsed[:targets] || [], &atomize_keys/1),
        issues: Enum.map(parsed[:issues] || [], &atomize_keys/1),
        files: Enum.map(parsed[:files] || [], &atomize_keys/1),
        cacheable_tasks: Enum.map(parsed[:cacheable_tasks] || [], &atomize_keys/1),
        cas_outputs: Enum.map(parsed[:cas_outputs] || [], &atomize_keys/1),
        machine_metrics: Enum.map(parsed[:machine_metrics] || [], &atomize_keys/1)
      })

    {:ok, _build} = Builds.create_build(attrs)
    :ok
  end

  defp mark_failed_build_processing(build_id, project_id, account_id, build_metadata) do
    attrs =
      Map.merge(base_build_attrs(build_id, account_id, build_metadata), %{
        project_id: project_id,
        status: "failed_processing",
        duration: 0
      })

    Builds.create_build(attrs)
  end

  defp base_build_attrs(build_id, account_id, build_metadata) do
    case Builds.get_build(build_id) do
      {:error, :not_found} ->
        Map.merge(
          %{id: build_id, account_id: account_id, is_ci: false},
          atomize_keys(build_metadata)
        )

      {:ok, existing_build} ->
        existing_build
        |> Map.from_struct()
        |> Map.drop([
          :__meta__,
          :project,
          :ran_by_account,
          :issues,
          :files,
          :targets,
          :machine_metrics,
          :cacheable_tasks_count,
          :cacheable_task_local_hits_count,
          :cacheable_task_remote_hits_count
        ])
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      other -> other
    end)
  end
end
