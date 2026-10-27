defmodule Tuist.Marketing.NimblePublisher.Content do
  @moduledoc false

  defmacro __using__(opts) do
    as = Keyword.fetch!(opts, :as)
    dev_from = Keyword.fetch!(opts, :dev_from)
    prod_from = Keyword.fetch!(opts, :prod_from)

    shared_opts =
      opts
      |> Keyword.delete(:as)
      |> Keyword.delete(:dev_from)
      |> Keyword.delete(:prod_from)

    dev_opts = Keyword.put(shared_opts, :from, dev_from)

    prod_opts =
      shared_opts
      |> Keyword.put(:as, as)
      |> Keyword.put(:from, prod_from)

    quote do
      if Mix.env() == :dev do
        @content_opts unquote(dev_opts)

        defp content_entries do
          Tuist.Marketing.NimblePublisher.Cache.entries(__MODULE__, @content_opts)
        end
      else
        @content_from Keyword.fetch!(unquote(prod_opts), :from)
        @content_paths @content_from |> Path.wildcard() |> Enum.sort()
        @content_paths_digest :erlang.md5(@content_paths)

        for path <- @content_paths do
          @external_resource Path.relative_to_cwd(path)
        end

        @content_entries Tuist.Marketing.NimblePublisher.Builder.build!(unquote(prod_opts))

        defp content_entries, do: @content_entries

        def __mix_recompile__? do
          @content_from |> Path.wildcard() |> Enum.sort() |> :erlang.md5() != @content_paths_digest
        end

        def __phoenix_recompile__?, do: __mix_recompile__?()
      end
    end
  end
end
