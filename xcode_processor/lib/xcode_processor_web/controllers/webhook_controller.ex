defmodule XcodeProcessorWeb.WebhookController do
  use XcodeProcessorWeb, :controller

  require Logger

  def process_xcresult(
        conn,
        %{
          "test_run_id" => test_run_id,
          "storage_key" => storage_key,
          "project_id" => project_id
        } = params
      ) do
    Logger.info("Processing xcresult for test run #{test_run_id} (storage_key: #{storage_key})")

    opts = [
      test_run_id: test_run_id,
      account_handle: params["account_handle"],
      project_handle: params["project_handle"]
    ]

    case XcodeProcessor.XCResultProcessor.process(storage_key, opts) do
      {:ok, parsed_data} ->
        parsed_data = Map.put(parsed_data, "project_id", project_id)

        conn
        |> put_status(:ok)
        |> json(parsed_data)

      {:error, reason} ->
        Logger.warning("Failed to process xcresult for test run #{test_run_id}: #{inspect(reason)}")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "processing_failed", detail: inspect(reason)})
    end
  end
end
