defmodule Atlas.Documents.Workers.EnsureDocumentClassificationsTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage
  alias Atlas.Documents.Workers.ClassifyDocumentMetadata
  alias Atlas.Documents.Workers.EnsureDocumentClassifications

  describe "EnsureDocumentClassifications.perform/1" do
    test "returns zero when there are no candidate documents" do
      assert {:ok, 0} = perform_job(EnsureDocumentClassifications, %{})
    end

    test "enqueues one classification job per candidate document" do
      first = insert_document!(%{title: "First Fallback", attributes: %{"classification" => %{"status" => "fallback"}}})
      second = insert_document!(%{title: "Second Fallback", summary: nil})
      failed = insert_document!(%{title: "Failed Fallback", attributes: %{"classification" => %{"status" => "failed"}}})
      _first_page = insert_document_page!(first, "First text")
      _second_page = insert_document_page!(second, "Second text")
      _failed_page = insert_document_page!(failed, "Failed text")

      assert {:ok, 2} = perform_job(EnsureDocumentClassifications, %{"limit" => 10})

      assert_enqueued(worker: ClassifyDocumentMetadata, args: %{"document_id" => first.id})
      assert_enqueued(worker: ClassifyDocumentMetadata, args: %{"document_id" => second.id})
      refute_enqueued(worker: ClassifyDocumentMetadata, args: %{"document_id" => failed.id})
    end
  end

  describe "ClassifyDocumentMetadata.perform/1" do
    test "cancels when the document does not exist" do
      assert {:cancel, :document_not_found} =
               perform_job(ClassifyDocumentMetadata, %{"document_id" => Ecto.UUID.generate()})
    end
  end

  defp insert_document!(attrs) do
    defaults = %{
      title: "Document",
      original_filename: "document.txt",
      content_type: "text/plain",
      byte_size: 10,
      checksum_sha256: "#{System.unique_integer([:positive])}",
      storage_bucket: "test-documents",
      storage_key: "documents/#{System.unique_integer([:positive])}.txt",
      status: "ready",
      source: "upload"
    }

    %Document{}
    |> Document.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_document_page!(%Document{} = document, content) do
    %DocumentPage{}
    |> DocumentPage.changeset(%{document_id: document.id, page_number: 1, content: content})
    |> Repo.insert!()
  end
end
