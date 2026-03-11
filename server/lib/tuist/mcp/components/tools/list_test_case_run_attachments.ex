defmodule Tuist.MCP.Components.Tools.ListTestCaseRunAttachments do
  @moduledoc """
  List attachments for a test case run. Each attachment includes a temporary download URL (valid for 1 hour).
  """

  @behaviour EMCP.Tool

  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.Storage
  alias Tuist.Tests

  @authorization_action :read
  @authorization_category :test

  @impl EMCP.Tool
  def name, do: "list_test_case_run_attachments"

  @impl EMCP.Tool
  def description,
    do: "List attachments for a test case run. Each attachment includes a temporary download URL (valid for 1 hour)."

  @impl EMCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "test_case_run_id" => %{
          "type" => "string",
          "description" => "The ID of the test case run."
        }
      },
      "required" => ["test_case_run_id"]
    }
  end

  @impl EMCP.Tool
  def call(conn, %{"test_case_run_id" => test_case_run_id}) do
    with {:ok, run} <-
           ToolSupport.load_resource(
             Tests.get_test_case_run_by_id(test_case_run_id, preload: [:attachments]),
             "Test case run not found: #{test_case_run_id}"
           ),
         {:ok, project} <-
           ToolSupport.authorize_project_by_id(
             conn.assigns,
             run.project_id,
             @authorization_action,
             @authorization_category
           ) do
      data = %{
        test_case_run_id: test_case_run_id,
        attachments:
          Enum.map(run.attachments || [], fn attachment ->
            s3_object_key =
              Tests.attachment_storage_key(%{
                account_handle: project.account.name,
                project_handle: project.name,
                test_case_run_id: test_case_run_id,
                attachment_id: attachment.id,
                file_name: attachment.file_name
              })

            %{
              id: attachment.id,
              file_name: attachment.file_name,
              type: attachment_type(attachment.file_name),
              download_url: Storage.generate_download_url(s3_object_key, project.account, expires_in: 3600)
            }
          end)
      }

      ToolSupport.json_response(data)
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  defp attachment_type(file_name) do
    ext = file_name |> String.downcase() |> Path.extname()

    cond do
      ext in [".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic"] -> "image"
      ext in [".txt"] -> "text"
      ext in [".log"] -> "log"
      ext in [".json"] -> "json"
      ext in [".xml"] -> "xml"
      ext in [".csv"] -> "csv"
      ext in [".ips"] -> "crash_report"
      true -> "file"
    end
  end
end
