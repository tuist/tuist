defmodule Cache.S3 do
  @moduledoc """
  S3 helper functions for generating presigned URLs.

  Isolated behind a module for easy testing without mutating global config.
  """

  require Logger

  def presign_download_url(key) when is_binary(key) do
    bucket = Application.get_env(:cache, :s3)[:bucket]
    config = ExAws.Config.new(:s3)
    ExAws.S3.presigned_url(config, :get, bucket, key, expires_in: 600)
  end

  @doc """
  Build the internal X-Accel-Redirect path used by nginx to proxy a remote URL.

  Always uses https and excludes any explicit port.

  Returns a path of the form:
    /internal/remote/https/<host>/<path>?<query>
  """
  def remote_accel_path(url) when is_binary(url) do
    %URI{host: host, path: path, query: query} = URI.parse(url)

    path = path || "/"

    base = "/internal/remote/https/" <> host <> path

    case query do
      nil -> base
      "" -> base
      _ -> base <> "?" <> query
    end
  end
end
