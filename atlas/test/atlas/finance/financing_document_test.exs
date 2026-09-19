defmodule Atlas.Finance.FinancingDocumentTest do
  use Atlas.DataCase, async: true

  import Atlas.FinancingsFixtures

  alias Atlas.Documents.Document
  alias Atlas.Finance.FinancingDocument
  alias Atlas.Finance.Financings

  test "attaches multiple typed documents to one financing" do
    financing = insert_financing!(%{supplier: "Apple"})
    supplier_contract = insert_document!("Apple supplier contract")
    financing_agreement = insert_document!("Targo financing agreement")
    guarantee = insert_document!("Personal guarantee")

    assert {:ok, _link} =
             Financings.attach_document(financing, supplier_contract.id, "supplier_contract")

    assert {:ok, _link} =
             Financings.attach_document(financing, financing_agreement.id, "financing_agreement")

    assert {:ok, _link} = Financings.attach_document(financing, guarantee.id, "guarantee")

    assert Enum.map(Financings.list_documents(financing), & &1.kind) == [
             "supplier_contract",
             "financing_agreement",
             "guarantee"
           ]
  end

  test "rejects a document whose upload is incomplete" do
    financing = insert_financing!()
    document = insert_document!("Pending contract", %{status: "pending_upload", byte_size: nil, checksum_sha256: nil})

    assert {:error, :document_not_ready} =
             Financings.attach_document(financing, document.id, "supplier_contract")
  end

  test "detaches the relationship without deleting the document" do
    financing = insert_financing!()
    document = insert_document!("Financing agreement")
    {:ok, link} = Financings.attach_document(financing, document.id, "financing_agreement")

    assert {:ok, %FinancingDocument{}} = Financings.detach_document(link.id)
    assert Repo.get(Document, document.id)
    assert Financings.list_documents(financing) == []
  end

  test "rejects an unknown document kind" do
    financing = insert_financing!()
    document = insert_document!("Unknown document")

    assert {:error, changeset} = Financings.attach_document(financing, document.id, "unknown")
    assert errors_on(changeset).kind == ["is invalid"]
  end

  defp insert_document!(title, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    defaults = %{
      title: title,
      original_filename: "financing-#{unique}.pdf",
      content_type: "application/pdf",
      byte_size: 100,
      checksum_sha256: String.duplicate("a", 64) <> Integer.to_string(unique),
      storage_bucket: "test-documents",
      storage_key: "financings/#{unique}.pdf",
      source: "upload",
      status: "ready"
    }

    %Document{}
    |> Document.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
