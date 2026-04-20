defmodule ProcessorWeb.WebhookController do
  use ProcessorWeb, :controller

  require Logger

  def process_build(
        conn,
        %{
          "build_id" => build_id,
          "storage_key" => storage_key,
          "project_id" => project_id
        } = params
      ) do
    xcode_cache_upload_enabled = Map.get(params, "xcode_cache_upload_enabled", false)
    Logger.info("Processing build #{build_id} (storage_key: #{storage_key})")

    case Processor.BuildProcessor.process(storage_key, xcode_cache_upload_enabled) do
      {:ok, parsed_data} ->
        parsed_data = Map.put(parsed_data, "project_id", project_id)

        conn
        |> put_status(:ok)
        |> json(parsed_data)

      {:error, reason} ->
        Logger.warning("Failed to process build #{build_id}: #{inspect(reason)}")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "processing_failed", detail: inspect(reason)})
    end
  end
end
