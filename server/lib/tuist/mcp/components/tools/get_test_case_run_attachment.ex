defmodule Tuist.MCP.Components.Tools.GetTestCaseRunAttachment do
  @moduledoc """
  Get a download URL for a test case run attachment. Use this to inspect crash reports, logs, screenshots, and other test artifacts.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.Storage
  alias Tuist.Tests

  @authorization_action :read
  @authorization_category :test

  schema do
    field :test_case_run_id, :string,
      required: true,
      description: "The ID of the test case run."

    field :attachment_id, :string,
      required: true,
      description: "The ID of the attachment (from list_test_case_run_attachments)."
  end

  @impl true
  def execute(%{test_case_run_id: test_case_run_id, attachment_id: attachment_id}, frame) do
    with {:ok, run} <-
           ToolSupport.load_resource(
             Tests.get_test_case_run_by_id(test_case_run_id, preload: [:attachments]),
             "Test case run not found: #{test_case_run_id}",
             frame
           ),
         {:ok, project} <-
           ToolSupport.authorize_project_by_id(
             frame,
             run.project_id,
             @authorization_action,
             @authorization_category
           ),
         {:ok, attachment} <- find_attachment(run.attachments || [], attachment_id, frame) do
      s3_object_key =
        Tests.attachment_storage_key(%{
          account_handle: project.account.name,
          project_handle: project.name,
          test_case_run_id: test_case_run_id,
          attachment_id: attachment.id,
          file_name: attachment.file_name
        })

      url = Storage.generate_download_url(s3_object_key, project.account, expires_in: 3600)

      data = %{
        id: attachment.id,
        file_name: attachment.file_name,
        download_url: url,
        expires_in_seconds: 3600
      }

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp find_attachment(attachments, attachment_id, frame) do
    case Enum.find(attachments, &(&1.id == attachment_id)) do
      nil -> ToolSupport.invalid_params("Attachment not found: #{attachment_id}", frame)
      attachment -> {:ok, attachment}
    end
  end
end
