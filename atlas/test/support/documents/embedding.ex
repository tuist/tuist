defmodule Atlas.TestSupport.Documents.Embedding do
  @moduledoc false

  def embed(text, _opts \\ []) do
    seed = :erlang.phash2(text, 1_000)
    value = seed / 1_000
    embedding = List.duplicate(value, 1536)
    {:ok, %{model: "test-embedding", embedding: embedding}}
  end
end
