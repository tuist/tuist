defmodule Tuist.XcodeMirror.Downloader do
  @moduledoc """
  Stream an Xcode .xip from Apple's CDN to a temp file, replaying
  the captured session cookies for auth.

  ## Streaming, not buffering

  A current Xcode .xip is ~10 GB. Buffering the body in memory
  would OOM the pod immediately; buffering to memory in chunks
  is wasteful. `Req`'s `:into` option streams chunks into a
  user-provided collectable — we pass a `File.stream!/3` write
  handle and the disk is the only thing that ever sees the full
  bytes.

  ## Signed URLs

  Apple's developer-portal download URLs look stable
  (`https://download.developer.apple.com/.../Xcode_<version>.xip`)
  but the actual `200 OK` requires the `myacinfo` + `dqsid`
  cookies in the session jar. A 401 / 403 means the cookies have
  expired; we surface that as a distinct return so the caller can
  emit `xcode_mirror.session_expired` instead of a generic error.

  ## Trust

  The bytes Apple ships are pkcs7-signed; `oras push` will
  content-address them on upload, so a corrupt download surfaces
  as a digest mismatch downstream. We don't verify the signature
  in this module — duplicating Apple's `xip(1)` verification logic
  in Elixir is more work than it's worth, and the downstream
  consumer (`xcodes install --path <xip>`) re-verifies anyway.
  """

  alias Tuist.XcodeMirror.AppleReleases
  alias Tuist.XcodeMirror.Session

  require Logger

  @doc """
  Download the .xip for `version` to `path`.

  Returns `{:ok, path}` on success. Possible errors:

    * `:no_download_url` — xcodereleases.com doesn't have a URL
      for this version (caller should skip).
    * `:session_expired` — Apple returned 401 / 403. Caller emits
      the session-expired Sentry alert.
    * `:no_session` — the cookie jar env var isn't configured;
      we never even attempted the download.
    * `{:bad_status, n}` — non-200 we don't otherwise know how to
      categorise. Logged with the status for debugging.
    * `{:network_error, _}` — transport failure.
  """
  def download(version, path, opts \\ []) do
    case Session.load(opts) do
      {:ok, cookies} -> do_download(version, path, cookies, opts)
      {:error, :missing} -> {:error, :no_session}
      {:error, _} = err -> err
    end
  end

  defp do_download(version, path, cookies, opts) do
    case AppleReleases.download_url(version, opts) do
      url when is_binary(url) -> stream_to_file(version, url, cookies, path)
      _ -> {:error, :no_download_url}
    end
  end

  defp stream_to_file(version, url, cookies, path) do
    File.mkdir_p!(Path.dirname(path))

    Logger.info("xcode_mirror: downloading Xcode #{version}",
      url: url,
      destination: path
    )

    # Stream the body straight to disk as chunks arrive. We don't
    # set `Accept`; Apple's CDN serves the .xip regardless. The
    # `User-Agent` matches xcodes' default — Apple has been known
    # to special-case requests with empty / suspicious UAs.
    file = File.stream!(path)

    result =
      Req.get(url,
        headers: [
          {"cookie", Session.to_cookie_header(cookies)},
          {"user-agent", "xcodes/1.6.0"}
        ],
        # Apple's CDN streams large bodies; 60s is plenty between
        # chunks but completion will take many minutes.
        receive_timeout: 60_000,
        connect_options: [timeout: 30_000],
        into: file,
        # Retry transient transport failures up to twice — Apple
        # occasionally serves a 502 mid-stream that succeeds on
        # immediate retry. Auth failures (401 / 403) are not
        # transient, don't retry.
        retry: fn _, response_or_exception ->
          retry?(response_or_exception)
        end,
        max_retries: 2
      )

    case result do
      {:ok, %Req.Response{status: 200}} ->
        size = File.stat!(path).size

        Logger.info("xcode_mirror: download complete",
          version: version,
          bytes: size
        )

        {:ok, path}

      {:ok, %Req.Response{status: status}} when status in [401, 403] ->
        File.rm(path)
        {:error, :session_expired}

      {:ok, %Req.Response{status: status}} ->
        File.rm(path)
        {:error, {:bad_status, status}}

      {:error, reason} ->
        File.rm(path)
        {:error, {:network_error, reason}}
    end
  end

  defp retry?(%Req.Response{status: status}) when status in 500..599, do: true
  defp retry?(%Req.TransportError{}), do: true
  defp retry?(%{__exception__: true}), do: true
  defp retry?(_), do: false
end
