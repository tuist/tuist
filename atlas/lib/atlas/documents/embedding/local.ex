defmodule Atlas.Documents.Embedding.Local do
  @moduledoc false

  def embed(text, _opts \\ []) when is_binary(text) do
    seed = :erlang.phash2(text, 10_000)
    base = seed / 10_000

    embedding =
      1..1536
      |> Enum.map(fn index ->
        :math.sin(base + index / 100) * 0.5 + 0.5
      end)

    {:ok, %{model: "local-hash-embedding", embedding: embedding}}
  end
end
