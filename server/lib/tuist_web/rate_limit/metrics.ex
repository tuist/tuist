defmodule TuistWeb.RateLimit.Metrics do
  @moduledoc """
  Rate limiting for the analytics APIs that read ClickHouse directly — build and
  test duration metrics, and the module cache analytics — protecting it from
  request floods. The fixed-window limit is keyed per authenticated subject, so
  the endpoints share one budget per caller.
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
