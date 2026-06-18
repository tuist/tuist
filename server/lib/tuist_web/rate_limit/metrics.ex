defmodule TuistWeb.RateLimit.Metrics do
  @moduledoc """
  Rate limiting for the build/test duration metrics API, protecting ClickHouse
  from request floods. Keyed per authenticated subject, in-memory token bucket.
  """

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit.InMemory

  @bucket_size 300

  def hit(conn) do
    InMemory.hit(key(conn), to_timeout(minute: 1), @bucket_size)
  end

  defp key(conn) do
    case Authentication.authenticated_subject(conn) do
      %AuthenticatedAccount{account: %{id: id}} -> "metrics:account:#{id}"
      %Project{id: id} -> "metrics:project:#{id}"
      %User{id: id} -> "metrics:user:#{id}"
      _ -> "metrics:unauth:#{TuistWeb.RemoteIp.get(conn)}"
    end
  end
end
