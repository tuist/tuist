defmodule TuistWeb.RateLimit.MCP do
  @moduledoc """
  Rate limiting for MCP endpoints.
  """

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Projects.Project
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit.InMemory

  def hit(conn) do
    {key, bucket_size} = key_and_bucket_size(conn)
    InMemory.hit(key, to_timeout(minute: 1), bucket_size)
  end

  defp key_and_bucket_size(conn) do
    case Authentication.authenticated_subject(conn) do
      nil ->
        {"mcp:unauth:#{TuistWeb.RemoteIp.get(conn)}", Tuist.Environment.mcp_rate_limit_bucket_size()}

      %User{id: id} ->
        {"mcp:auth:user:#{id}", Tuist.Environment.mcp_rate_limit_bucket_size()}

      %Project{id: id} ->
        {"mcp:auth:project:#{id}", Tuist.Environment.mcp_rate_limit_bucket_size()}

      %AuthenticatedAccount{account: %{id: id}} ->
        {"mcp:auth:account:#{id}", Tuist.Environment.mcp_rate_limit_bucket_size()}
    end
  end
end
