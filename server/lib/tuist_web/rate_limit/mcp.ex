defmodule TuistWeb.RateLimit.MCP do
  @moduledoc """
  Rate limiting for MCP endpoints.
  """

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit

  def hit(conn) do
    {key, failure_policy} = key_and_policy(conn)

    RateLimit.hit(key,
      limit: Tuist.Environment.mcp_rate_limit_bucket_size(),
      window: to_timeout(minute: 1),
      failure_policy: failure_policy
    )
  end

  defp key_and_policy(conn) do
    case Authentication.authenticated_subject(conn) do
      nil ->
        {"mcp:unauth:#{TuistWeb.RemoteIp.get(conn)}", :deny}

      %User{id: id} ->
        {"mcp:auth:user:#{id}", :local}

      %Project{id: id} ->
        {"mcp:auth:project:#{id}", :local}

      %AuthenticatedAccount{account: %{id: id}} ->
        {"mcp:auth:account:#{id}", :local}
    end
  end
end
