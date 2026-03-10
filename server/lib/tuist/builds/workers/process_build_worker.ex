defmodule Tuist.Builds.Workers.ProcessBuildWorker do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Tuist.Accounts
  alias Tuist.Builds
  alias Tuist.Storage

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "build_id" => build_id,
          "storage_key" => storage_key,
          "account_id" => account_id,
          "project_id" => project_id
        } = args
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
        replace_build_run(build_id, project_id, account_id, parsed_data)

      {:error, reason} ->
        mark_build_failed(build_id, project_id, account_id)
        {:error, reason}
    end
  end

  defp process_locally(build_id, storage_key, account_id, xcode_cache_upload_enabled) do
    if Code.ensure_loaded?(Processor.BuildProcessor) do
      Logger.info("Processing build #{build_id} locally")

      with {:ok, account} <- Accounts.get_account_by_id(account_id),
           build_bytes when is_binary(build_bytes) <- Storage.get_object_as_string(storage_key, account) do
        Processor.BuildProcessor.process_build(build_bytes, xcode_cache_upload_enabled)
      else
        nil -> {:error, :build_not_found}
        {:error, _} = error -> error
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

    Logger.info("Sending build #{build_id} to processor at #{processor_url}")

    json_body = Jason.encode!(payload)
    webhook_secret = Tuist.Environment.processor_webhook_secret() || ""

    signature =
      :crypto.mac(:hmac, :sha256, webhook_secret, json_body)
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
        Logger.info(
          "Processor returned parsed data for build #{build_id}: " <>
            "#{length(Map.get(parsed_data, "targets", []))} targets, " <>
            "#{length(Map.get(parsed_data, "issues", []))} issues, " <>
            "#{length(Map.get(parsed_data, "files", []))} files, " <>
            "#{length(Map.get(parsed_data, "cacheable_tasks", []))} cacheable_tasks, " <>
            "#{length(Map.get(parsed_data, "cas_outputs", []))} cas_outputs"
        )

        {:ok, parsed_data}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Processor returned #{status} for build #{build_id}: #{inspect(body)}")
        {:error, "processor_error_#{status}: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("Processor request failed for build #{build_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp replace_build_run(build_id, project_id, account_id, parsed_data) do
    Logger.info("Fetching original processing build #{build_id} from ClickHouse")
    original_build = Builds.get_build(build_id)

    if original_build do
      Logger.info("Found original build #{build_id} (status: #{original_build.status})")
    else
      Logger.warning("Original build #{build_id} not found in ClickHouse, proceeding without metadata")
    end

    parsed = atomize_keys(parsed_data)

    base_attrs =
      if original_build do
        original_build
        |> Map.from_struct()
        |> Map.drop([:__meta__, :project, :ran_by_account, :issues, :files, :targets])
      else
        %{id: build_id, project_id: project_id, account_id: account_id, is_ci: false}
      end

    attrs =
      Map.merge(base_attrs, %{
        duration: parsed[:duration] || 0,
        status: parsed[:status] || "success",
        category: parsed[:category],
        targets: convert_targets(parsed[:targets] || []),
        issues: convert_issues(parsed[:issues] || []),
        files: convert_files(parsed[:files] || []),
        cacheable_tasks: convert_cacheable_tasks(parsed[:cacheable_tasks] || []),
        cas_outputs: Enum.map(parsed[:cas_outputs] || [], &atomize_keys/1)
      })

    Logger.info(
      "Writing parsed build #{build_id} to ClickHouse (status: #{attrs[:status]}, duration: #{attrs[:duration]}ms)"
    )

    case Builds.create_build(attrs) do
      {:ok, _build} ->
        Logger.info("Successfully wrote build #{build_id} to ClickHouse")
        :ok

      {:error, changeset} ->
        Logger.error("Failed to create build #{build_id}: #{inspect(changeset.errors)}")
        {:error, "failed_to_create_build"}
    end
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
    Enum.map(files, fn f ->
      f = atomize_keys(f)
      Map.update!(f, :type, &String.to_existing_atom/1)
    end)
  end

  defp convert_issues(issues) do
    Enum.map(issues, fn i ->
      i = atomize_keys(i)

      i
      |> Map.update!(:type, &String.to_existing_atom/1)
      |> Map.update!(:step_type, &String.to_existing_atom/1)
    end)
  end

  defp convert_targets(targets) do
    Enum.map(targets, fn t ->
      t = atomize_keys(t)
      Map.update!(t, :status, &String.to_existing_atom/1)
    end)
  end

  defp convert_cacheable_tasks(tasks) do
    Enum.map(tasks, fn t ->
      t = atomize_keys(t)

      t
      |> Map.update!(:type, &String.to_existing_atom/1)
      |> Map.update!(:status, &String.to_existing_atom/1)
    end)
  end
end
