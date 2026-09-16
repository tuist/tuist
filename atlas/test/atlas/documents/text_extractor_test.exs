defmodule Atlas.Documents.TextExtractorTest do
  use ExUnit.Case, async: true

  alias Atlas.Documents.TextExtractor

  @sample_xlsx "test/commercial/support/fixtures/sample.xlsx"

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
end
