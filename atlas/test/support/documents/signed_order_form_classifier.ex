defmodule Atlas.TestSupport.Documents.SignedOrderFormClassifier do
  @moduledoc false

  def classify(document, _pages) do
    {:ok,
     %{
       title: document.title,
       document_type: "order_form",
       correspondent: "Acme Corp",
       document_date: ~D[2026-06-10],
       tags: ["order_form", "signed"],
       summary: "Signed order form for the annual subscription.",
       attributes: %{
         "signed" => true,
         "currency" => "USD",
         "total_amount" => "16200.00",
         "start_date" => "2026-05-02",
         "end_date" => "2027-05-01"
       }
     }}
  end
end
