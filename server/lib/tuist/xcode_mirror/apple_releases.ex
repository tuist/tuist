defmodule Tuist.XcodeMirror.AppleReleases do
  @moduledoc """
  Client for the public [xcodereleases.com](https://xcodereleases.com)
  data feed — the canonical machine-readable list of every Xcode
  Apple has shipped, including pre-releases.

  We use this feed (not Apple's own download portal) for the
  *listing* step of the mirror reconcile loop because the feed is:

    * **Auth-free.** No Apple session needed. Hitting Apple's own
      download portal for the version list would require the same
      cookie jar we're trying to confine to the .xip-download step
      only.
    * **Stable.** xcodereleases.com has been maintained by the
      `xcodereleases` project (and the broader iOS dev community)
      since 2019; it's the upstream data source the
      `XcodesApp/xcodes` CLI itself uses.
    * **Structured.** A JSON array of release records, each with a
      version string, a build number, a download URL, and release
      metadata. Easier than scraping Apple's HTML.

  ## Filtering

  By default we only mirror *GA* releases (`release.release == true`).
  Betas and release-candidates land in the same feed but with
  different release-type fields; piping those into the mirror would
  bloat GHCR with versions no customer pins. The release-tracking
  branch ships GA; ad-hoc beta mirroring goes through the
  `mise xcode-mirror:upload <version>` break-glass.

  ## Failure modes

    * `:network_error` — Req returned a transport error. Retry next
      tick; xcodereleases.com is normally reachable.
    * `:bad_status` — non-200 HTTP. Either xcodereleases.com is
      down (rare) or they moved the data feed (we'd ship a fix).
    * `:parse_error` — feed returned 200 but the JSON doesn't match
      our expected shape. Same fix path — they changed their
      schema.
  """

  alias Tuist.Environment

  require Logger

  @default_feed_url "https://xcodereleases.com/data.json"

  @doc """
  Fetch the list of *released* Xcode versions from xcodereleases.com.

  Returns `{:ok, ["26.5", "26.4.1", "26.4", ...]}` on success.
  Versions are returned in the patch-form `"X.Y[.Z]"` shape with
  no `Xcode` prefix — same shape the `xcode_version` Packer
  variable expects.

  ## Options

    * `:feed_url` — override the default xcodereleases.com URL
      (test injection).
    * `:include_prereleases` — when true, also return beta / RC
      versions. Default `false`; the worker pins to false in
      steady state.
  """
  def list_released(opts \\ []) do
    feed_url = Keyword.get(opts, :feed_url, feed_url())
    include_prereleases = Keyword.get(opts, :include_prereleases, false)

    case Req.get(feed_url, receive_timeout: 30_000, retry: :transient) do
      {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
        {:ok, extract_versions(body, include_prereleases)}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("xcode_mirror: xcodereleases feed returned non-200",
          status: status,
          url: feed_url
        )

        {:error, {:bad_status, status}}

      {:error, reason} ->
        Logger.warning("xcode_mirror: xcodereleases feed transport error",
          reason: inspect(reason)
        )

        {:error, {:network_error, reason}}
    end
  end

  @doc """
  Resolve a version string to its Apple-CDN download URL.

  `nil` when the version isn't in the feed (Apple yanked it, the
  feed hasn't caught up, the caller mis-typed the version).
  Returned URL is auth-walled — fetching it requires the session
  cookie jar.
  """
  def download_url(version, opts \\ []) do
    feed_url = Keyword.get(opts, :feed_url, feed_url())

    with {:ok, %Req.Response{status: 200, body: body}} when is_list(body) <-
           Req.get(feed_url, receive_timeout: 30_000, retry: :transient),
         entry when is_map(entry) <- find_entry(body, version) do
      get_in(entry, ["links", "download", "url"])
    else
      _ -> nil
    end
  end

  defp feed_url do
    Environment.get([:xcode_mirror, :feed_url], Environment.secrets()) || @default_feed_url
  end

  defp extract_versions(entries, include_prereleases) do
    entries
    |> Enum.filter(&released?(&1, include_prereleases))
    |> Enum.map(&format_version/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  # Feed shape (per a representative entry):
  #
  #   {
  #     "version": {
  #       "number": "26.4.1",
  #       "build": "17E202",
  #       "release": {"release": true}
  #     },
  #     "links": {
  #       "download": {"url": "https://download.developer.apple.com/.../Xcode_26.4.1.xip"}
  #     }
  #   }
  #
  # Pre-release entries set `release` to `{"beta": 1}` /
  # `{"rc": 2}` instead of `{"release": true}`.
  defp released?(entry, include_prereleases) do
    release = get_in(entry, ["version", "release"]) || %{}

    cond do
      Map.get(release, "release") == true -> true
      include_prereleases and map_size(release) > 0 -> true
      true -> false
    end
  end

  defp format_version(entry) do
    case get_in(entry, ["version", "number"]) do
      n when is_binary(n) and n != "" -> n
      _ -> nil
    end
  end

  defp find_entry(entries, version) do
    Enum.find(entries, fn entry -> format_version(entry) == version end)
  end
end
