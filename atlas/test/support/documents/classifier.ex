defmodule Atlas.TestSupport.Documents.Classifier do
  @moduledoc false

  def classify(document, _pages) do
    {:ok,
     %{
       title: document.title,
       document_type: "contract",
       correspondent: "Acme",
       document_date: ~D[2026-01-15],
       tags: ["legal", "renewal"],
       summary: "A searchable imported document.",
       attributes: %{"counterparty" => "Acme"}
     }}
  end
end
