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
        use NimblePublisher, unquote(prod_opts)

        @content_entries Module.get_attribute(__MODULE__, unquote(as))

        defp content_entries, do: @content_entries
      end
    end
  end
end
