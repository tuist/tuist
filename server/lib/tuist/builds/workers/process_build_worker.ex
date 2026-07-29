defmodule Tuist.Builds.Workers.ProcessBuildWorker do
  @moduledoc """
  Oban worker that parses an uploaded xcactivitylog archive and writes the
  structured build run.

  In the managed deployment the `:process_build` queue only runs on processor
  pods (`TUIST_MODE=processor`), so this worker's body executes there;
  the server pods enqueue jobs but never claim them. In self-hosted installs
  the server runs both roles in the same BEAM.

  ## Uniqueness

  Jobs are unique on `build_id` over `available | scheduled | executing |
  retryable` with `period: :infinity` to absorb the duplicate enqueues from
  the race in `get_or_create_build`. A re-enqueue while a previous job is
  still in-flight (or sitting in retryable) is silently dropped — to manually
  requeue a stuck job, cancel the existing one first.
  """

  use Oban.Worker,
    queue: :process_build,
    max_attempts: 5,
    unique: [
      keys: [:build_id],
      states: [:available, :scheduled, :executing, :retryable],
      period: :infinity
    ]

  alias Tuist.Builds
  alias Tuist.Projects
  alias Tuist.Storage

  require Logger

  # Cap one job's wall time so a single huge xcactivitylog cannot hold a worker
  # slot indefinitely. The NIF's internal timeout is set lower so it returns
  # a structured error first; this is the outer guard for everything else.
  @impl Oban.Worker
  def timeout(_job), do: to_timeout(minute: 5)

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

    case process_build(build_id, storage_key, project_id, xcode_cache_upload_enabled) do
      {:ok, parsed_data} ->
        parsed_data = Map.put(parsed_data, "project_id", project_id)
        replace_build_run(build_id, parsed_data, account_id, project_id, build_metadata)

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

  # Storage routes per account, so the download backend must be the project's
  # account (where the artifact was uploaded and the key is namespaced), not
  # the run's `account_id`, which records who ran the build and can be a member
  # with a different personal account.
  defp process_build(build_id, storage_key, project_id, xcode_cache_upload_enabled) do
    with {:ok, account} <- storage_account(project_id) do
      # Unique per execution: the duplicate-enqueue race in `get_or_create_build`
      # can leave two jobs running for the same build_id concurrently. A path
      # keyed only on build_id makes them share one file — one job's download (or
      # its `File.rm` cleanup) corrupts/removes the archive the other is mid-read,
      # surfacing as a spurious xcactivitylog parse error.
      temp_path = Path.join(System.tmp_dir!(), "build_#{build_id}_#{System.unique_integer([:positive])}.zip")

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

  defp storage_account(project_id) do
    case Projects.get_project_by_id(project_id) do
      nil -> {:error, :project_not_found}
      project -> {:ok, project.account}
    end
  end

  defp replace_build_run(build_id, parsed_data, account_id, project_id, build_metadata) do
    parsed = atomize_keys(parsed_data)

    attrs =
      Map.merge(base_build_attrs(build_id, project_id, account_id, build_metadata), %{
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
      Map.merge(base_build_attrs(build_id, project_id, account_id, build_metadata), %{
        project_id: project_id,
        status: "failed_processing",
        duration: 0
      })

    Builds.create_build(attrs)
  end

  defp base_build_attrs(build_id, project_id, account_id, build_metadata) do
    case Builds.get_build(build_id, project_id: project_id) do
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
