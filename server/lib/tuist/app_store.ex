defmodule Tuist.AppStore do
  @moduledoc ~S"""
  Fetches and caches the latest Tuist iOS app version from the App Store
  lookup API, used to surface the iOS app download on the marketing site.
  Results are cached with a 1-hour TTL to minimize API calls, mirroring
  `Tuist.GitHub.Releases`.
  """

  alias Tuist.KeyValueStore

  require Logger

  @ios_app_id "6748460335"
  @ios_app_url "https://apps.apple.com/app/tuist/id#{@ios_app_id}"
  @lookup_url "https://itunes.apple.com/lookup?id=#{@ios_app_id}"
  @ttl to_timeout(hour: 1)

  def ios_app_url do
    @ios_app_url
  end

  def get_latest_ios_app_version(opts \\ []) do
    if Tuist.Environment.dev?() do
      nil
    else
      KeyValueStore.get_or_update(
        [__MODULE__, "app_store_latest_ios_app_version"],
        [ttl: Keyword.get(opts, :ttl, @ttl)],
        fn ->
          fetch_latest_ios_app_version()
        end
      )
    end
  end

  defp fetch_latest_ios_app_version do
    case Req.get(@lookup_url, finch: Tuist.Finch) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse_version(body)

      {:ok, %Req.Response{status: status}} ->
        Logger.error("Failed to fetch the App Store listing, status: #{status}")
        nil

      {:error, reason} ->
        Logger.error("Failed to fetch the App Store listing, reason: #{inspect(reason)}")
        nil
    end
  end

  # The lookup API responds with a text/javascript content type, so Req may
  # hand the body back as a raw string instead of a decoded map.
  defp parse_version(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, decoded} -> parse_version(decoded)
      {:error, _} -> nil
    end
  end

  defp parse_version(%{"results" => [%{"version" => version} | _]}) do
    version
  end

  defp parse_version(_body), do: nil
end
