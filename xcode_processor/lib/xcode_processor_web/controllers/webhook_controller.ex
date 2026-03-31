defmodule XcodeProcessorWeb.WebhookController do
  use XcodeProcessorWeb, :controller

  require Logger

  def process_xcresult(
        conn,
        %{
          "test_run_id" => test_run_id,
          "storage_key" => storage_key,
          "project_id" => project_id
        }
      ) do
    Logger.info("Processing xcresult for test run #{test_run_id} (storage_key: #{storage_key})")

    {:ok, parsed_data} = XcodeProcessor.XCResultProcessor.process(storage_key)
    parsed_data = Map.put(parsed_data, "project_id", project_id)

    conn
    |> put_status(:ok)
    |> json(parsed_data)
  end
end
