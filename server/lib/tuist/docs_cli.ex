defmodule Tuist.Docs.CLI do
  @moduledoc """
  Fetches and caches the CLI spec from the latest GitHub release,
  then generates documentation pages for each CLI command.
  """

  alias Tuist.Docs.CLI.Renderer

  require Logger

  @repo "tuist/tuist"
  @cache_key :cli_spec_data
  @ttl :timer.hours(1)

  def get_pages do
    case load() do
      %{pages: pages} -> pages
      nil -> []
    end
  end

  def get_page(slug) do
    case load() do
      %{pages_by_slug: pages_by_slug} -> Map.get(pages_by_slug, slug)
      nil -> nil
    end
  end

  def sidebar_items do
    case load() do
      %{sidebar_items: items} -> items
      nil -> []
    end
  end

  defp load do
    case Cachex.get(:tuist, @cache_key) do
      {:ok, nil} -> fetch_and_cache()
      {:ok, data} -> data
      _ -> nil
    end
  end

  defp fetch_and_cache do
    case fetch_spec() do
      {:ok, spec} ->
        pages = Renderer.build_pages(spec)
        data = %{
          pages: pages,
          pages_by_slug: Map.new(pages, &{&1.slug, &1}),
          sidebar_items: Renderer.build_sidebar(spec)
        }

        Cachex.put(:tuist, @cache_key, data, ttl: @ttl)
        data

      {:error, reason} ->
        Logger.warning("Failed to fetch CLI spec: #{inspect(reason)}")
        nil
    end
  end

  defp fetch_spec do
    with {:ok, tag} <- fetch_latest_cli_tag(),
         {:ok, spec} <- fetch_spec_json(tag) do
      {:ok, spec}
    end
  end

  defp fetch_latest_cli_tag do
    url = "https://api.github.com/repos/#{@repo}/releases?per_page=20"

    case Req.get(url, headers: github_headers()) do
      {:ok, %{status: 200, body: releases}} ->
        cli_release =
          Enum.find(releases, fn release ->
            tag = release["tag_name"] || ""
            not String.contains?(tag, "@")
          end)

        case cli_release do
          nil -> {:error, :no_cli_release}
          release -> {:ok, release["tag_name"]}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_spec_json(tag) do
    url = "https://github.com/#{@repo}/releases/download/#{tag}/tuist.spec.json"

    case Req.get(url, headers: github_headers()) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        Jason.decode(body)

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp github_headers do
    token = System.get_env("GITHUB_TOKEN")

    base = [{"accept", "application/json"}, {"user-agent", "tuist-server"}]

    if token do
      [{"authorization", "Bearer #{token}"} | base]
    else
      base
    end
  end
end
