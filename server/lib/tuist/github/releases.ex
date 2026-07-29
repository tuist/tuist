defmodule Tuist.GitHub.Releases do
  @moduledoc ~S"""
  Fetches and caches the latest Tuist App release from GitHub, used to surface
  the macOS app download in the dashboard. Results are cached with a 1-hour TTL
  to minimize API calls.
  """

  alias Tuist.GitHub.Retry
  alias Tuist.KeyValueStore

  require Logger

  @releases_url "https://api.github.com/repos/tuist/tuist/releases"
  @ttl to_timeout(hour: 1)

  def releases_url do
    @releases_url
  end

  def get_latest_app_release(opts \\ []) do
    if Tuist.Environment.dev?() do
      nil
    else
      KeyValueStore.get_or_update(
        [__MODULE__, "github_latest_app_release"],
        [ttl: Keyword.get(opts, :ttl, @ttl)],
        fn ->
          fetch_latest_app_release()
        end
      )
    end
  end

  defp github_auth_headers do
    case Tuist.Environment.github_token_update_package_releases() do
      nil ->
        []

      token ->
        [
          {"Accept", "application/vnd.github.v3+json"},
          {"Authorization", "Bearer #{token}"}
        ]
    end
  end

  defp map_release(release) do
    %{
      name: release["name"],
      tag_name: release["tag_name"],
      published_at: Timex.parse!(release["published_at"], "{ISO:Extended}"),
      html_url: release["html_url"],
      assets:
        Enum.map(
          release["assets"],
          &%{name: &1["name"], browser_download_url: &1["browser_download_url"]}
        )
    }
  end

  defp fetch_latest_app_release(opts \\ []) do
    url = Keyword.get(opts, :url, releases_url())

    case release_page(url, opts) do
      %{releases: releases, next_url: next_url} ->
        case find_app_release_from_releases(releases) do
          nil when next_url != nil ->
            fetch_latest_app_release(Keyword.put(opts, :url, next_url))

          result ->
            result
        end

      nil ->
        nil
    end
  end

  defp release_page(url, opts) do
    KeyValueStore.get_or_update(
      [__MODULE__, "github_releases_page", url],
      [ttl: Keyword.get(opts, :ttl, @ttl)],
      fn ->
        fetch_release_page(url)
      end
    )
  end

  defp fetch_release_page(url) do
    headers = github_auth_headers()
    req_opts = [finch: Tuist.Finch, headers: headers] ++ Retry.retry_options()

    case Req.get(url, req_opts) do
      {:ok, %Req.Response{status: 200, body: releases, headers: headers}} ->
        %{
          releases: Enum.map(releases, &map_release/1),
          next_url: extract_next_url(headers)
        }

      {:ok, %Req.Response{status: status}} when status in 500..599 ->
        Logger.error("Failed to fetch GitHub releases, status: #{status}")
        nil

      {:ok, %Req.Response{status: status}} ->
        Logger.error("Failed to fetch GitHub releases, status: #{status}")
        nil

      {:error, reason} ->
        Logger.error("Failed to fetch GitHub releases, reason: #{inspect(reason)}")
        nil
    end
  end

  defp find_app_release_from_releases(releases) do
    Enum.find(releases, fn release ->
      String.starts_with?(release.tag_name, "app@") and
        Enum.find(release.assets, &String.ends_with?(&1.browser_download_url, "dmg"))
    end)
  end

  defp extract_next_url(headers) do
    Enum.find_value(headers, fn
      {"link", [link_header | _]} ->
        parse_link_header(link_header)

      _ ->
        nil
    end)
  end

  defp parse_link_header(link_header) do
    # Parse GitHub's Link header format: <url>; rel="next"
    case Regex.run(~r/<([^>]+)>;\s*rel="next"/, link_header) do
      [_, next_url] -> next_url
      _ -> nil
    end
  end
end
