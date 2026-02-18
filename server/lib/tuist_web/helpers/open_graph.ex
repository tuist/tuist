defmodule TuistWeb.Helpers.OpenGraph do
  @moduledoc """
  Helper functions for generating Open Graph meta tag assigns.
  """

  @doc """
  Returns default Open Graph assigns for dashboard pages.
  """
  def og_image_assigns do
    [head_twitter_card: "summary_large_image"]
  end

  @doc """
  Returns Open Graph assigns for dashboard pages with explicit key-values.
  """
  def og_image_assigns(key_values) when is_list(key_values) do
    [
      head_twitter_card: "summary_large_image",
      head_open_graph_key_values: key_values
    ]
  end

  def og_image_assigns(_key_values), do: og_image_assigns()

  @doc """
  Builds semantic Open Graph key-values for a page.
  """
  def semantic_key_values(page, section, focus) do
    [
      %{key: "Page", value: semantic_value(page, "Overview")},
      %{key: "Section", value: semantic_value(section, "Project")},
      %{key: "Focus", value: semantic_value(focus, "Overview")}
    ]
  end

  defp semantic_value(value, fallback) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> fallback
      value -> value
    end
  end
end
