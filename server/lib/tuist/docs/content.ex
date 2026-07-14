defmodule Tuist.Docs.Content do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      alias Tuist.Docs.NimblePublisher.Cache

      defp static_pages, do: Cache.pages()
      defp static_page(slug), do: Cache.get_page(slug)
      defp static_slugs, do: Cache.slugs()
    end
  end
end
