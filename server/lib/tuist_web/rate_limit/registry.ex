defmodule TuistWeb.RateLimit.Registry do
  @moduledoc """
  Rate limiting for Swift package registry endpoints.

  Applies different rate limits based on authentication status:
  - Unauthenticated requests: Lower limit (default: 100 requests)
  - Authenticated requests: Higher limit (default: 10000 requests)
  """
  import Plug.Conn

  alias Tuist.Environment
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit.InMemory
  alias TuistWeb.RateLimit.PersistentTokenBucket

  def init(opts), do: opts

  def call(%Plug.Conn{} = conn, _opts) do
    if Environment.tuist_hosted?() do
      case hit(conn) do
        {:allow, _count} ->
          conn

        {:deny, _limit} ->
          conn
          |> put_status(:too_many_requests)
          |> Phoenix.Controller.json(%{
            message: "You have made too many requests to the registry. Please try again later."
          })
          |> halt()
      end
    else
      conn
    end
  end

  defp hit(conn) do
    authenticated? = not is_nil(Authentication.authenticated_subject(conn))

    {key, bucket_size} =
      if authenticated? do
        {
          "registry:auth:#{get_subject_id(conn)}",
          10_000
        }
      else
        {
          "registry:unauth:#{TuistWeb.RemoteIp.get(conn)}",
          1_000
        }
      end

    if is_nil(Environment.redis_url()) do
      InMemory.hit(key, to_timeout(minute: 1), bucket_size)
    else
      # 1 token per minute
      fill_rate = 1 / 60
      tokens_per_hit = 1
      PersistentTokenBucket.hit(key, fill_rate, bucket_size, tokens_per_hit)
    end
  end

  defp get_subject_id(conn) do
    case Authentication.authenticated_subject(conn) do
      %{id: id} -> id
      %{account: %{id: id}} -> id
      _ -> TuistWeb.RemoteIp.get(conn)
    end
  end
end
