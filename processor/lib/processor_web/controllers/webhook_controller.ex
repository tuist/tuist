defmodule ProcessorWeb.WebhookController do
  use ProcessorWeb, :controller

  require Logger

  def process_build(conn, %{
        "build_id" => build_id,
        "storage_key" => storage_key,
        "account_id" => account_id,
        "project_id" => project_id
      }) do
    Logger.info("Processing build #{build_id} (storage_key: #{storage_key})")

    case Processor.BuildProcessor.process(storage_key, account_id) do
      {:ok, parsed_data} ->
        parsed_data = Map.put(parsed_data, "project_id", project_id)

        conn
        |> put_status(:ok)
        |> json(parsed_data)

      {:error, reason} ->
        Logger.error("Failed to process build #{build_id}: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: inspect(reason)})
    end
  end
end
