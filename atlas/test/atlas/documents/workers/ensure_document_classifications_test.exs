defmodule Atlas.Documents.Workers.EnsureDocumentClassificationsTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage
  alias Atlas.Documents.Workers.ClassifyDocumentMetadata
  alias Atlas.Documents.Workers.EnsureDocumentClassifications
  alias Atlas.Finance
  alias Atlas.Finance.Agents.InvoiceExtractorAgent

  describe "EnsureDocumentClassifications.perform/1" do
    test "returns zero when there are no candidate documents" do
      assert {:ok, 0} = perform_job(EnsureDocumentClassifications, %{})
    end

    test "enqueues repair for an already classified invoice without extracted text" do
      invoice_type = Documents.upsert_document_type("invoice")

      document =
        insert_document!(%{
          title: "Cloudflare invoice",
          document_date: ~D[2026-09-30],
          attributes: %{"classification" => %{"status" => "classified", "source" => "deterministic"}}
        })

      document
      |> Ecto.Changeset.change(document_type_id: invoice_type.id)
      |> Repo.update!()

      assert {:ok, 1} = perform_job(EnsureDocumentClassifications, %{})
      assert {:ok, 0} = perform_job(EnsureDocumentClassifications, %{})
      assert [%{args: %{"document_id" => document_id}}] = all_enqueued(worker: ClassifyDocumentMetadata)
      assert document_id == document.id
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
    test "retries transient extraction failures before recording a final failure" do
      document =
        insert_document!(%{
          title: "Archived document",
          document_date: ~D[2026-09-30],
          attributes: %{"classification" => %{"status" => "classified", "source" => "deterministic"}}
        })

      invoice_type = Documents.upsert_document_type("invoice")
      document |> Ecto.Changeset.change(document_type_id: invoice_type.id) |> Repo.update!()
      insert_document_page!(document, "Service charges $100.00")
      expect(InvoiceExtractorAgent, :extract, 2, fn _document, _pages -> {:error, :timeout} end)

      job = %Oban.Job{args: %{"document_id" => document.id}, attempt: 1, max_attempts: 3}
      assert {:error, :timeout} = ClassifyDocumentMetadata.perform(job)
      assert Finance.get_finance_invoice_by_document(document) == nil
      assert Documents.list_document_classification_candidate_ids() == [document.id]

      assert :ok = ClassifyDocumentMetadata.perform(%{job | attempt: 3})
      assert %{status: "failed", last_error: ":timeout"} = Finance.get_finance_invoice_by_document(document)
      assert Documents.list_document_classification_candidate_ids() == []
    end

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
