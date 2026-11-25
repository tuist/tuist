defmodule Atlas.Documents.TextExtractorTest do
  use ExUnit.Case, async: true

  alias Atlas.Documents.TextExtractor

  @sample_xlsx "test/support/fixtures/sample.xlsx"

  describe "extract_pages/3 for xlsx" do
    test "renders a per-sheet outline covering names, columns, and sample rows" do
      assert {:ok, [%{page_number: 1, content: content} | _]} =
               TextExtractor.extract_pages(@sample_xlsx, nil, "roster.xlsx")

      assert content =~ "Spreadsheet: roster.xlsx"
      assert content =~ "Sheets: 1 (People)"
      assert content =~ "## Sheet: People"
      assert content =~ "Columns: Name | Role"
      assert content =~ "Ada | Engineer"
      assert content =~ "Grace | Engineer"
    end

    test "detects xlsx by mime type as well" do
      content_type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

      assert {:ok, [%{content: content} | _]} =
               TextExtractor.extract_pages(@sample_xlsx, content_type, "no-extension")

      assert content =~ "## Sheet: People"
    end
  end

  describe "extract_pages/3 for docx" do
    @tag :tmp_dir
    test "reports an unambiguous error when pandoc is not installed on the runner", %{tmp_dir: tmp_dir} do
      if System.find_executable("pandoc") do
        # pandoc is present: at least confirm we do not fall through to
        # :unsupported_document_type for a docx-suffixed path.
        path = Path.join(tmp_dir, "note.docx")
        File.write!(path, "not-really-docx-but-detect-the-suffix")
        assert result = TextExtractor.extract_pages(path, nil, "note.docx")
        refute match?({:error, :unsupported_document_type}, result)
      else
        assert {:error, :pandoc_not_found} =
                 TextExtractor.extract_pages(Path.join(tmp_dir, "missing.docx"), nil, "missing.docx")
      end
    end
  end

  describe "extract_pages/3 for unsupported types" do
    @tag :tmp_dir
    test "returns :unsupported_document_type for other binaries", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "image.png")
      File.write!(path, <<0, 1, 2>>)

      assert {:error, :unsupported_document_type} =
               TextExtractor.extract_pages(path, "image/png", "image.png")
    end
  end

  describe "extract_pages/3 for text-like content" do
    @tag :tmp_dir
    test "splits plain text on form-feed page breaks", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "notes.txt")
      File.write!(path, "page one\n\fpage two")

      assert {:ok, pages} = TextExtractor.extract_pages(path, "text/plain", "notes.txt")
      assert Enum.map(pages, & &1.page_number) == [1, 2]
      assert Enum.map(pages, & &1.content) == ["page one", "page two"]
    end

    # DOCX text has no page breaks, so a long document is one page split into
    # several chunks. Page numbers are unique per document, so every chunk
    # needs its own number.
    @tag :tmp_dir
    test "numbers every chunk of a long page and keeps its source page", %{tmp_dir: tmp_dir} do
      paragraph = String.duplicate("Liability is capped at fees paid. ", 200)
      path = Path.join(tmp_dir, "annex.txt")
      File.write!(path, Enum.join(List.duplicate(paragraph, 4), "\n\n") <> "\fshort second page")

      assert {:ok, pages} = TextExtractor.extract_pages(path, "text/plain", "annex.txt")
      assert length(pages) > 2
      assert Enum.map(pages, & &1.page_number) == Enum.to_list(1..length(pages))
      assert pages |> Enum.drop(-1) |> Enum.map(& &1.metadata["source_page"]) |> Enum.uniq() == [1]
      assert %{content: "short second page", metadata: %{"source_page" => 2}} = List.last(pages)
    end

    # Scanned-image PDFs (e.g. phone-camera receipts converted to PDF) carry
    # no text layer, so pdftotext produces empty output. The extractor must
    # surface that as zero pages rather than an error, so downstream
    # classification can still run from filename and attributes instead of
    # leaving the document stuck as failed.
    @tag :tmp_dir
    test "returns an empty page list when the source has no extractable text", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "blank.txt")
      File.write!(path, "")

      assert {:ok, []} = TextExtractor.extract_pages(path, "text/plain", "blank.txt")
    end
  end

  describe "extract_pages/3 for zip archives" do
    @tag :tmp_dir
    test "extracts supported files in name order and skips the rest", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "package.zip")

      {:ok, _path} =
        :zip.create(String.to_charlist(path), [
          {~c"b/terms.md", "Terms of service"},
          {~c"logo.png", <<137, 80, 78, 71>>},
          {~c"__MACOSX/a/._notes.txt", "resource fork"},
          {~c"a/notes.txt", "Order form notes\fsecond page"}
        ])

      assert {:ok, pages} = TextExtractor.extract_pages(path, "application/zip", "package.zip")

      assert Enum.map(pages, &{&1.page_number, &1.content, &1.metadata["archive_entry"]}) == [
               {1, "Order form notes", "a/notes.txt"},
               {2, "second page", "a/notes.txt"},
               {3, "Terms of service", "b/terms.md"}
             ]
    end

    @tag :tmp_dir
    test "completes with no pages when nothing inside is readable", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "images.zip")
      {:ok, _path} = :zip.create(String.to_charlist(path), [{~c"logo.png", <<137, 80, 78, 71>>}])

      assert {:ok, []} = TextExtractor.extract_pages(path, nil, "images.zip")
    end

    @tag :tmp_dir
    test "fails a file that is not a zip", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "broken.zip")
      File.write!(path, "not a zip")

      assert {:error, :zip_extraction_failed} = TextExtractor.extract_pages(path, "application/zip", "broken.zip")
    end
  end
end
