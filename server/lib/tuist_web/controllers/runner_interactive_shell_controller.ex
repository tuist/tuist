defmodule TuistWeb.RunnerInteractiveShellController do
  use TuistWeb, :controller

  import Plug.Conn

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Authorization
  alias Tuist.Runners.InteractiveSessions
  alias TuistWeb.Authentication
  alias TuistWeb.RunnerShellClientWebSock

  @token_protocol_pattern ~r/^[A-Za-z0-9_-]{32,128}$/

  def connect(conn, %{"account_handle" => account_handle}) do
    current_user = Authentication.current_user(conn)

    with {:ok, token} <- shell_token(conn),
         %Account{} = account <- Accounts.get_account_by_handle(account_handle),
         %User{} <- current_user,
         :ok <- Authorization.authorize(:runners_read, current_user, account),
         {:ok, session} <- InteractiveSessions.validate_token(token, account, current_user),
         :ok <- validate_shell_session(session) do
      conn
      |> WebSockAdapter.upgrade(
        RunnerShellClientWebSock,
        %{session: %{session | token: token}},
        timeout: to_timeout(minute: 65)
      )
      |> halt()
    else
      _ ->
        conn
        |> send_resp(:not_found, "")
        |> halt()
    end
  end

  def shell_token(conn) do
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

  def validate_shell_session(%{kind: :shell, state: state}) when state in [:requested, :ready, :active], do: :ok
  def validate_shell_session(_session), do: {:error, :not_ready}
end
