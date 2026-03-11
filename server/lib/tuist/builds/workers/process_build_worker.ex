defmodule Tuist.Builds.Workers.ProcessBuildWorker do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Tuist.Accounts
  alias Tuist.Builds
  alias Tuist.Storage

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{"build_id" => build_id, "storage_key" => storage_key, "account_id" => account_id, "project_id" => project_id} =
            args
      }) do
    processor_url = Tuist.Environment.processor_url()
    xcode_cache_upload_enabled = Map.get(args, "xcode_cache_upload_enabled", false)

    result =
      if is_nil(processor_url) or processor_url == "" do
        process_locally(build_id, storage_key, account_id, xcode_cache_upload_enabled)
      else
        send_to_processor(processor_url, build_id, storage_key, account_id, project_id, xcode_cache_upload_enabled)
      end

    case result do
      {:ok, parsed_data} ->
        parsed_data = Map.put(parsed_data, "project_id", project_id)
        replace_build_run(build_id, parsed_data)

      {:error, reason} ->
        mark_build_failed(build_id, project_id, account_id)
        {:error, reason}
    end
  end

  @processor_module Processor.BuildProcessor

  defp process_locally(build_id, storage_key, account_id, xcode_cache_upload_enabled) do
    if Code.ensure_loaded?(@processor_module) do
      with {:ok, account} <- Accounts.get_account_by_id(account_id) do
        temp_path = Path.join(System.tmp_dir!(), "build_#{build_id}.zip")

        try do
          case Storage.download_to_file(storage_key, temp_path, account) do
            {:ok, _} ->
              apply(@processor_module, :process_build, [temp_path, xcode_cache_upload_enabled])

            {:error, _} = error ->
              error
          end
        after
          File.rm(temp_path)
        end
      end
    else
      Logger.error(
        "No processor available for build #{build_id}: processor_url not configured and Processor.BuildProcessor not loaded"
      )

      {:error, "processor_not_available"}
    end
  end

  defp send_to_processor(processor_url, build_id, storage_key, account_id, project_id, xcode_cache_upload_enabled) do
    payload = %{
      build_id: build_id,
      storage_key: storage_key,
      account_id: account_id,
      project_id: project_id,
      xcode_cache_upload_enabled: xcode_cache_upload_enabled
    }

    json_body = Jason.encode!(payload)
    webhook_secret = Tuist.Environment.processor_webhook_secret() || ""

    signature =
      :hmac
      |> :crypto.mac(:sha256, webhook_secret, json_body)
      |> Base.encode16(case: :lower)

    case Req.post("#{processor_url}/webhooks/process-build",
           body: json_body,
           headers: [
             {"content-type", "application/json"},
             {"x-webhook-signature", signature}
           ],
           receive_timeout: 300_000
         ) do
      {:ok, %{status: 200, body: parsed_data}} ->
        {:ok, parsed_data}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Processor returned #{status} for build #{build_id}: #{inspect(body)}")
        {:error, "processor_error_#{status}: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("Processor request failed for build #{build_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp replace_build_run(build_id, parsed_data) do
    parsed = atomize_keys(parsed_data)

    base_attrs =
      build_id
      |> Builds.get_build()
      |> Map.from_struct()
      |> Map.drop([:__meta__, :project, :ran_by_account, :issues, :files, :targets])

    attrs =
      Map.merge(base_attrs, %{
        project_id: parsed[:project_id],
        duration: parsed[:duration] || 0,
        status: parsed[:status] || "success",
        category: parsed[:category],
        targets: convert_targets(parsed[:targets] || []),
        issues: convert_issues(parsed[:issues] || []),
        files: convert_files(parsed[:files] || []),
        cacheable_tasks: convert_cacheable_tasks(parsed[:cacheable_tasks] || []),
        cas_outputs: Enum.map(parsed[:cas_outputs] || [], &atomize_keys/1),
        machine_metrics: convert_machine_metrics(parsed[:machine_metrics] || [])
      })

    {:ok, _build} = Builds.create_build(attrs)
    :ok
  end

  defp mark_build_failed(build_id, project_id, account_id) do
    Builds.create_build(%{
      id: build_id,
      project_id: project_id,
      account_id: account_id,
      status: "failed_processing",
      duration: 0,
      is_ci: false
    })
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      other -> other
    end)
  end

  defp convert_files(files) do
    Enum.map(files, fn file ->
      file = atomize_keys(file)
      Map.update!(file, :type, &String.to_existing_atom/1)
    end)
  end

  defp convert_issues(issues) do
    Enum.map(issues, fn issue ->
      issue = atomize_keys(issue)

      issue
      |> Map.update!(:type, &String.to_existing_atom/1)
      |> Map.update!(:step_type, &String.to_existing_atom/1)
    end)
  end

  defp convert_targets(targets) do
    Enum.map(targets, fn target ->
      target = atomize_keys(target)
      Map.update!(target, :status, &String.to_existing_atom/1)
    end)
  end

  defp convert_machine_metrics(metrics) do
    Enum.map(metrics, fn metric ->
      %{
        timestamp: metric["timestamp"],
        cpu_usage_percent: metric["cpuUsagePercent"],
        memory_used_bytes: metric["memoryUsedBytes"],
        memory_total_bytes: metric["memoryTotalBytes"],
        network_bytes_in: metric["networkBytesIn"],
        network_bytes_out: metric["networkBytesOut"],
        disk_bytes_read: metric["diskBytesRead"],
        disk_bytes_written: metric["diskBytesWritten"]
      }
    end)
  end

  defp convert_cacheable_tasks(tasks) do
    Enum.map(tasks, fn task ->
      task = atomize_keys(task)

      task
      |> Map.update!(:type, &String.to_existing_atom/1)
      |> Map.update!(:status, &String.to_existing_atom/1)
    end)
  end
end
