defmodule Atlas.TestSupport.Documents.FailingClassifier do
  @moduledoc false

  def classify(_document, _pages), do: {:error, {:session_exit, :timeout}}
end
