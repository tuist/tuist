defmodule TuistWeb.API.RunnerInteractiveShellController do
  use TuistWeb, :controller

  import Plug.Conn

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Authorization
  alias Tuist.Runners.InteractiveSessions
  alias TuistWeb.Authentication
  alias TuistWeb.RunnerInteractiveShellController
  alias TuistWeb.RunnerShellClientWebSock

  def connect(conn, _params) do
    current_user = Authentication.current_user(conn)

    with {:ok, token} <- RunnerInteractiveShellController.shell_token(conn),
         %User{} <- current_user,
         {:ok, session} <- InteractiveSessions.validate_token(token, current_user),
         :ok <- RunnerInteractiveShellController.validate_shell_session(session),
         {:ok, account} <- Accounts.get_account_by_id(session.account_id),
         :ok <- Authorization.authorize(:runners_read, current_user, account) do
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
end
