defmodule TuistWeb.Runs.CacheEndpointFormatter do
  @moduledoc """
  Helper module for formatting cache endpoint URLs into human-readable region names.
  """

  @doc """
  Returns a list of cache endpoint options for use in filters.
  Includes an empty string option for "tuist.dev" at the beginning.
  """
  def cache_endpoint_options do
    ["" | Tuist.Environment.cache_endpoints()]
  end

  @doc """
  Returns a map of cache endpoint URLs to their display names.
  """
  def cache_endpoint_display_names(none_label) do
    Tuist.Environment.cache_endpoints()
    |> Map.new(fn endpoint -> {endpoint, format_cache_endpoint(endpoint)} end)
    |> Map.put("", none_label)
  end

  @doc """
  Formats a cache endpoint URL into a human-readable region name.

  ## Examples

      iex> format_cache_endpoint("https://cache-eu-central.tuist.dev")
      "EU Central"

      iex> format_cache_endpoint("https://cache-us-east.tuist.dev")
      "US East"

      iex> format_cache_endpoint("")
      "tuist.dev"

  """
  def format_cache_endpoint(""), do: "tuist.dev"
  def format_cache_endpoint(nil), do: "tuist.dev"

  def format_cache_endpoint(endpoint) do
    case Regex.run(~r/cache-([a-z-]+)\.tuist\.dev/, endpoint) do
      [_, "eu-central"] ->
        "EU Central"

      [_, "us-east"] ->
        "US East"

      [_, "us-west"] ->
        "US West"

      [_, "ap-southeast"] ->
        "Asia Pacific Southeast"

      [_, region] ->
        region
        |> String.replace("-", " ")
        |> String.split()
        |> Enum.map_join(" ", &String.capitalize/1)

      _ ->
        endpoint
    end
  end
end
