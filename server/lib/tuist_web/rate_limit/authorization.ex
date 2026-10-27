defmodule TuistWeb.RateLimit.Authorization do
  @moduledoc """
  Rate limiting for API requests an authenticated subject is not authorized to make.

  Counts only denied requests, so a client working within its permissions is never
  throttled no matter how much traffic it sends.
  """

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Environment
  alias Tuist.Projects.Project
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit
  alias TuistWeb.RemoteIp

  def hit(conn) do
    RateLimit.hit(
      key(conn),
      limit: Environment.authorization_denial_rate_limit_bucket_size(),
      window: to_timeout(minute: 1)
    )
  end

  defp key(conn) do
    case Authentication.authenticated_subject(conn) do
      %User{id: id} -> "authorization-denied:user:#{id}"
      %Project{id: id} -> "authorization-denied:project:#{id}"
      %AuthenticatedAccount{account: %{id: id}} -> "authorization-denied:account:#{id}"
      _ -> "authorization-denied:ip:#{RemoteIp.get(conn)}"
    end
  end
end
