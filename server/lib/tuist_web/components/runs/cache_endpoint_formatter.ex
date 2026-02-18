defmodule TuistWeb.Runs.CacheEndpointFormatter do
  @moduledoc """
  Helper module for formatting cache endpoint URLs into human-readable region names.
  """

  @doc """
  Returns a list of cache endpoint options for use in filters.
  Includes an empty string option for "tuist.dev" at the beginning.
  """
  def cache_endpoint_options do
    endpoints = Enum.map(Tuist.CacheEndpoints.list_cache_endpoints(), & &1.url)

    ["" | endpoints]
  end

  @doc """
  Returns a map of cache endpoint URLs to their display names.
  """
  def cache_endpoint_display_names(none_label) do
    Tuist.CacheEndpoints.list_cache_endpoints()
    |> Map.new(fn endpoint -> {endpoint.url, endpoint.display_name} end)
    |> Map.put("", none_label)
  end

  @doc """
  Returns the display name for a cache endpoint URL.
  Looks up the display name from the database first, falling back to URL-based formatting.
  """
  def display_name_for_endpoint(url) when url in ["", nil], do: "tuist.dev"

  def display_name_for_endpoint(url) do
    case Tuist.CacheEndpoints.get_cache_endpoint_by_url(url) do
      {:ok, endpoint} -> endpoint.display_name
      {:error, :not_found} -> format_cache_endpoint(url)
    end
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
