defmodule Atlas.TestSupport.Documents.NoopInvoiceExtractor do
  @moduledoc false

  def extract(_document, _pages), do: {:error, :skipped}
end
