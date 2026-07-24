defmodule TuistWeb.RateLimit.Metrics do
  @moduledoc """
  Rate limiting for the build/test duration metrics API, protecting ClickHouse
  from request floods. The fixed-window limit is keyed per authenticated subject.
  """

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit

  @bucket_size 300

  def hit(conn) do
    RateLimit.hit(key(conn), limit: @bucket_size, window: to_timeout(minute: 1))
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
