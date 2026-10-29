defmodule Atlas.Documents.DocumentPageTest do
  use Atlas.DataCase, async: true

  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage

  describe "schema" do
    test "metadata defaults to an empty map" do
      assert %DocumentPage{}.metadata == %{}
    end
  end

  describe "changeset/2" do
    test "requires document_id, page_number, and content" do
      changeset = DocumentPage.changeset(%DocumentPage{}, %{})

      refute changeset.valid?

      assert errors_on(changeset) == %{
               document_id: ["can't be blank"],
               page_number: ["can't be blank"],
               content: ["can't be blank"]
             }
    end

    test "is valid with the required fields" do
      document = insert_document!()

      changeset =
        DocumentPage.changeset(%DocumentPage{}, %{
          document_id: document.id,
          page_number: 1,
          content: "First page text"
        })

      assert changeset.valid?
    end

    test "casts the optional embedding and metadata fields" do
      document = insert_document!()
      embedded_at = ~U[2026-01-15 10:00:00Z]

      changeset =
        DocumentPage.changeset(%DocumentPage{}, %{
          document_id: document.id,
          page_number: 2,
          content: "Second page text",
          embedding_model: "fireworks/qwen3-embedding-8b",
          embedded_at: embedded_at,
          metadata: %{"language" => "en"}
        })

      assert changeset.valid?
      assert get_change(changeset, :embedding_model) == "fireworks/qwen3-embedding-8b"
      assert get_change(changeset, :embedded_at) == embedded_at
      assert get_change(changeset, :metadata) == %{"language" => "en"}
    end

    test "rejects non-positive page numbers" do
      document = insert_document!()

      changeset =
        DocumentPage.changeset(%DocumentPage{}, %{
          document_id: document.id,
          page_number: 0,
          content: "x"
        })

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).page_number
    end

    test "enforces a unique page number per document" do
      document = insert_document!()

      assert {:ok, _page} =
               %DocumentPage{}
               |> DocumentPage.changeset(%{document_id: document.id, page_number: 1, content: "a"})
               |> Repo.insert()

      assert {:error, changeset} =
               %DocumentPage{}
               |> DocumentPage.changeset(%{document_id: document.id, page_number: 1, content: "b"})
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).document_id
    end

    test "allows the same page number across different documents" do
      first = insert_document!()
      second = insert_document!()

      assert {:ok, _} =
               %DocumentPage{}
               |> DocumentPage.changeset(%{document_id: first.id, page_number: 1, content: "a"})
               |> Repo.insert()

      assert {:ok, _} =
               %DocumentPage{}
               |> DocumentPage.changeset(%{document_id: second.id, page_number: 1, content: "b"})
               |> Repo.insert()
    end
  end

  defp insert_document!(attrs \\ %{}) do
    defaults = %{
      "title" => "Service Agreement",
      "original_filename" => "service-agreement.pdf",
      "content_type" => "application/pdf",
      "byte_size" => 1024,
      "checksum_sha256" => unique("checksum"),
      "storage_bucket" => "test-documents",
      "storage_key" => "#{unique("documents/ab/")}.pdf",
      "source" => "upload",
      "status" => "uploaded"
    }

    %Document{}
    |> Document.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
