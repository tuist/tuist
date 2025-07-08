defmodule TuistWeb.Flop do
  @moduledoc """
  Module that provides Flop utilities.
  """

  @page_size 20

  def get_options_with_before_and_after(options, attrs) do
    cond do
      not is_nil(Keyword.get(attrs, :before)) ->
        options
        |> Map.put(:last, @page_size)
        |> Map.put(:before, Keyword.get(attrs, :before))

      not is_nil(Keyword.get(attrs, :after)) ->
        options
        |> Map.put(:first, @page_size)
        |> Map.put(:after, Keyword.get(attrs, :after))

      true ->
        Map.put(options, :first, @page_size)
    end
  end
end
