defmodule Tuist.XcodeMirror.Registry do
  @moduledoc """
  Talk to our own `ghcr.io/tuist/xcode-xips` OCI repository over
  the standard [OCI Distribution
  Spec](https://github.com/opencontainers/distribution-spec) HTTP
  API. We don't go through `oras` for the listing step — `oras
  repo tags` would work but adds a binary dep at runtime and a
  Port.open layer for a single GET, and our needs are simple
  enough to do directly.

  ## Auth

  GHCR uses an OAuth2-flavoured bearer-token dance:

    1. The first request to `/v2/<repo>/tags/list` returns 401
       with a `Www-Authenticate` header carrying the token URL and
       scope.
    2. We POST to that token URL with basic auth (the
       `TUIST_XCODE_MIRROR_GHCR_USERNAME` /
       `TUIST_XCODE_MIRROR_GHCR_TOKEN` env vars — a tuist-bot PAT
       with `read:packages` is sufficient for listing) and parse
       the returned bearer token.
    3. Retry the original request with the token.

  Tokens are short-lived (5 min) and listed-scope-only, so we
  don't bother caching them across worker ticks — the auth dance
  on a 6h cadence is cheap.

  ## Push

  Listing is plenty for the read-only Phase 2 worker. The push
  side of the equation goes through the `oras` CLI in Phase 3 —
  implementing chunked OCI blob uploads in pure Elixir is doable
  but tedious, and `oras` is a stable enough tool that shelling
  out is the pragmatic choice.
  """

  alias Tuist.Environment

  require Logger

  @default_registry "ghcr.io"
  @default_repository "tuist/xcode-xips"

  @doc """
  List every tag currently published under our `xcode-xips`
  repository.

  Returns `{:ok, ["26.5", "26.4.1", ...]}` on success. The order
  isn't guaranteed by the registry; callers that need a
  deterministic shape sort.

  Errors:
    * `:network_error` — transport-level failure.
    * `:bad_status` — registry returned a non-200 we don't expect
      (most often a misconfigured token).
    * `:auth_required` — the registry asked for auth but no token
      is configured. Surfaces a clear runbook-friendly message
      instead of looping on 401s.
  """
  def list_mirrored_tags(opts \\ []) do
    registry = Keyword.get(opts, :registry, registry())
    repository = Keyword.get(opts, :repository, repository())
    url = "https://#{registry}/v2/#{repository}/tags/list"

    case fetch_tags(url, opts) do
      {:ok, tags} -> {:ok, tags}
      {:error, _} = err -> err
    end
  end

  defp fetch_tags(url, opts) do
    case Req.get(url, headers: [{"accept", "application/json"}], receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: %{"tags" => tags}}} when is_list(tags) ->
        {:ok, tags}

      {:ok, %Req.Response{status: 200, body: %{"tags" => nil}}} ->
        # Empty repo: GHCR returns `{"name": ..., "tags": null}` on
        # first publish before any blob lands.
        {:ok, []}

      {:ok, %Req.Response{status: 401, headers: headers}} ->
        case bearer_token(headers, opts) do
          {:ok, token} -> fetch_tags_with_token(url, token)
          {:error, _} = err -> err
        end

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("xcode_mirror: registry listing returned non-200",
          status: status,
          url: url
        )

        {:error, {:bad_status, status}}

      {:error, reason} ->
        Logger.warning("xcode_mirror: registry listing transport error",
          reason: inspect(reason)
        )

        {:error, {:network_error, reason}}
    end
  end

  defp fetch_tags_with_token(url, token) do
    case Req.get(url,
           headers: [
             {"accept", "application/json"},
             {"authorization", "Bearer #{token}"}
           ],
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"tags" => tags}}} when is_list(tags) ->
        {:ok, tags}

      {:ok, %Req.Response{status: 200, body: %{"tags" => nil}}} ->
        {:ok, []}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:bad_status, status}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  # Implements the GHCR bearer-token dance. The Www-Authenticate
  # header looks like:
  #
  #   Bearer realm="https://ghcr.io/token",service="ghcr.io",scope="repository:tuist/xcode-xips:pull"
  #
  # We POST to `realm` with basic auth + the params from the header
  # and parse `{"token": "..."}` out of the response.
  defp bearer_token(headers, opts) do
    auth_header = get_header(headers, "www-authenticate") || ""

    with {:ok, %{"realm" => realm} = challenge} <- parse_auth_challenge(auth_header),
         {:ok, username, password} <- ghcr_credentials(opts) do
      params =
        challenge
        |> Map.delete("realm")
        |> Map.to_list()

      case Req.get(realm,
             params: params,
             auth: {:basic, "#{username}:#{password}"},
             receive_timeout: 15_000
           ) do
        {:ok, %Req.Response{status: 200, body: %{"token" => token}}} ->
          {:ok, token}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:bad_status, status}}

        {:error, reason} ->
          {:error, {:network_error, reason}}
      end
    end
  end

  defp parse_auth_challenge("Bearer " <> rest) do
    params =
      rest
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.flat_map(fn pair ->
        case String.split(pair, "=", parts: 2) do
          [k, v] -> [{String.trim(k), String.trim(v, "\"")}]
          _ -> []
        end
      end)
      |> Map.new()

    case Map.fetch(params, "realm") do
      {:ok, _} -> {:ok, params}
      :error -> {:error, :auth_challenge_missing_realm}
    end
  end

  defp parse_auth_challenge(_), do: {:error, :auth_challenge_unparseable}

  defp ghcr_credentials(opts) do
    username =
      Keyword.get(opts, :ghcr_username) ||
        Environment.get([:xcode_mirror, :ghcr_username], Environment.secrets()) ||
        "tuist-bot"

    token =
      Keyword.get(opts, :ghcr_token) ||
        Environment.get([:xcode_mirror, :ghcr_token], Environment.secrets())

    if is_binary(token) and token != "" do
      {:ok, username, token}
    else
      {:error, :auth_required}
    end
  end

  defp get_header(headers, name) when is_list(headers) do
    name_down = String.downcase(name)

    Enum.find_value(headers, fn
      {k, v} when is_binary(k) ->
        if String.downcase(k) == name_down, do: v

      _ ->
        nil
    end)
  end

  defp get_header(headers, name) when is_map(headers) do
    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(to_string(k)) == String.downcase(name),
        do: v |> List.wrap() |> List.first()
    end)
  end

  defp registry do
    Environment.get([:xcode_mirror, :registry], Environment.secrets()) || @default_registry
  end

  defp repository do
    Environment.get([:xcode_mirror, :repository], Environment.secrets()) || @default_repository
  end
end
