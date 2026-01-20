defmodule TuistWeb.RateLimit.Registry do
  @moduledoc """
  Rate limiting for registry endpoints.
  """
  import Plug.Conn

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Projects.Project
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit.InMemory

  def init(opts), do: opts

  def call(%Plug.Conn{} = conn, _opts) do
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
  end

  defp hit(conn) do
    authenticated? = not is_nil(Authentication.authenticated_subject(conn))

    {key, bucket_size} =
      if authenticated? do
        {
          "registry:auth:#{get_subject_key(conn)}",
          100_000
        }
      else
        {
          "registry:unauth:#{TuistWeb.RemoteIp.get(conn)}",
          10_000
        }
      end

    InMemory.hit(key, to_timeout(minute: 1), bucket_size)
  end

  defp get_subject_key(conn) do
    case Authentication.authenticated_subject(conn) do
      %Project{id: id} -> "project:#{id}"
      %AuthenticatedAccount{account: %{id: id}} -> "account:#{id}"
    end
  end
end
