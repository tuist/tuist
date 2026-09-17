defmodule Atlas.MCP.Tools.DocumentUploadToolsTest do
  use Atlas.MCP.ToolCase
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Documents.Document
  alias Atlas.Documents.Storage
  alias Atlas.Documents.Workers.ProcessDocument
  alias Atlas.MCP.Tools.CreateDocumentUpload
  alias Atlas.MCP.Tools.FinalizeDocumentUpload
  alias Atlas.Repo

  describe "create_document_upload" do
    test "reserves a pending row and returns the presigned URL for an executive" do
      conn = executive_mcp_conn()

      assert {:ok, payload} =
               execute_tool(CreateDocumentUpload, conn, %{
                 "original_filename" => "renewal.pdf",
                 "content_type" => "application/pdf"
               })

      assert payload.upload_method == "PUT"
      assert payload.required_headers == %{"Content-Type" => "application/pdf"}
      assert is_binary(payload.upload_url) and payload.upload_url != ""
      assert payload.upload_expires_at =~ ~r/^\d{4}-\d{2}-\d{2}T/

      document = Repo.get!(Document, payload.document_id)
      assert document.status == "pending_upload"
      assert document.content_type == "application/pdf"
    end

    test "rejects a non-executive user" do
      conn = insert_user!() |> mcp_conn()

      assert {:error, message} =
               CreateDocumentUpload.execute(conn, %{
                 "original_filename" => "x.pdf",
                 "content_type" => "application/pdf"
               })

      assert message =~ "executives"
    end

    test "surfaces missing arguments explicitly" do
      conn = executive_mcp_conn()

      assert {:error, "original_filename and content_type are required."} =
               CreateDocumentUpload.execute(conn, %{})
    end
  end

  describe "finalize_document_upload" do
    test "promotes a pending row and enqueues processing after the bytes are in storage" do
      conn = executive_mcp_conn()

      {:ok, %{document_id: document_id}} =
        execute_tool(CreateDocumentUpload, conn, %{
          "original_filename" => "renewal.pdf",
          "content_type" => "application/pdf"
        })

      document = Repo.get!(Document, document_id)
      {:ok, _object} = Storage.put_object(document.storage_key, "some bytes")

      assert {:ok, payload} =
               execute_tool(FinalizeDocumentUpload, conn, %{"document_id" => document_id})

      assert payload.document_id == document_id
      assert payload.status == "uploaded"
      assert payload.byte_size == byte_size("some bytes")
      assert payload.checksum_sha256 =~ ~r/^[0-9a-f]{64}$/

      assert_enqueued(worker: ProcessDocument, args: %{"document_id" => document_id})
    end

    test "refuses to finalize a document whose bytes never arrived" do
      conn = executive_mcp_conn()

      {:ok, %{document_id: document_id}} =
        execute_tool(CreateDocumentUpload, conn, %{
          "original_filename" => "renewal.pdf",
          "content_type" => "application/pdf"
        })

      assert {:error, message} = FinalizeDocumentUpload.execute(conn, %{"document_id" => document_id})
      assert message =~ "has not landed"
    end

    test "returns a clear error when the document does not exist" do
      conn = executive_mcp_conn()

      assert {:error, "Document not found."} =
               FinalizeDocumentUpload.execute(conn, %{"document_id" => Ecto.UUID.generate()})
    end
  end
end
