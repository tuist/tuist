defmodule AtlasWeb.DocumentLinksTest do
  use ExUnit.Case, async: true

  alias Atlas.Documents.Document
  alias AtlasWeb.DocumentLinks

  test "builds a download path from the document title" do
    document = %Document{
      id: "document-id",
      title: "SafetyCulture Pty Ltd",
      original_filename: "download",
      content_type: "application/pdf"
    }

    assert DocumentLinks.download_filename(document) == "safetyculture-pty-ltd.pdf"
    assert DocumentLinks.download_path(document) == "/documents/document-id/download/safetyculture-pty-ltd.pdf"
  end

  test "keeps the original extension when it is available" do
    document = %Document{
      id: "document-id",
      title: "Acme MSA",
      original_filename: "signed-contract.TXT",
      content_type: "text/plain"
    }

    assert DocumentLinks.download_filename(document) == "acme-msa.txt"
  end
end
