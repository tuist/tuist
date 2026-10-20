defmodule Tuist.VCS.RemoteURL do
  @moduledoc """
  CI checkouts often authenticate through the remote itself
  (`https://x-access-token:<token>@github.com/org/repo.git`), so the origin URL
  the CLI reports can carry a live credential. Strip it at ingestion so it never
  lands in job arguments or error reports.
  """

  @doc """
  Removes the userinfo component from a URL remote. scp-style remotes
  (`git@github.com:org/repo.git`) have no URI scheme and are returned unchanged.
  """
  def strip_credentials(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{userinfo: nil} -> url
      %URI{host: host} = uri when is_binary(host) -> URI.to_string(%{uri | userinfo: nil})
      _ -> url
    end
  end

  def strip_credentials(url), do: url

  @doc """
  Applies `strip_credentials/1` to the `git_remote_url_origin` entry of a map,
  whether it is keyed by atom (request params) or string (Oban job args).
  """
  def strip_credentials_from_params(params) when is_map(params) do
    Enum.reduce([:git_remote_url_origin, "git_remote_url_origin"], params, fn key, params ->
      case params do
        %{^key => url} -> Map.put(params, key, strip_credentials(url))
        _ -> params
      end
    end)
  end
end
