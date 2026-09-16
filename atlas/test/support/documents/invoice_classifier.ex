defmodule Atlas.TestSupport.Documents.InvoiceClassifier do
  @moduledoc false

  def classify(document, _pages) do
    {:ok,
     %{
       title: document.title,
       document_type: "invoice",
       correspondent: "Cloudflare, Inc.",
       document_date: ~D[2026-05-15],
       tags: ["invoice", "cloudflare"],
       summary: "Invoice from Cloudflare, Inc.",
       attributes: %{}
     }}
  end
end
