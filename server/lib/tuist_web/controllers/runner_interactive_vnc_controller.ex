defmodule TuistWeb.RunnerInteractiveVNCController do
  use TuistWeb, :controller

  import Plug.Conn

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Authorization
  alias Tuist.Runners.InteractiveSessions
  alias TuistWeb.Authentication
  alias TuistWeb.RunnerVNCWebSock

  @token_protocol_pattern ~r/^[A-Za-z0-9_-]{32,128}$/

  def connect(conn, %{"account_handle" => account_handle}) do
    current_user = Authentication.current_user(conn)

    with {:ok, token} <- vnc_token(conn),
         %Account{} = account <- Accounts.get_account_by_handle(account_handle),
         %User{} <- current_user,
         :ok <- Authorization.authorize(:runners_read, current_user, account),
         {:ok, session} <- InteractiveSessions.validate_token(token, account, current_user),
         :ok <- validate_vnc_session(session) do
      conn
      |> WebSockAdapter.upgrade(RunnerVNCWebSock, %{session: %{session | token: token}}, timeout: to_timeout(minute: 65))
      |> halt()
    else
      _ ->
        conn
        |> send_resp(:not_found, "")
        |> halt()
    end
  end

  defp vnc_token(conn) do
    conn
    |> get_req_header("sec-websocket-protocol")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.find(&Regex.match?(@token_protocol_pattern, &1))
    |> case do
      token when is_binary(token) -> {:ok, token}
      nil -> {:error, :missing_token}
    end
  end

  defp validate_vnc_session(%{kind: :vnc, state: state, relay_host: host, relay_port: port})
       when state in [:ready, :active] and is_binary(host) and host != "" and is_integer(port) and port > 0 and
              port <= 65_535, do: :ok

  defp validate_vnc_session(_session), do: {:error, :not_ready}
end
