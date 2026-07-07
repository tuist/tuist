defmodule TuistWeb.RunnerInteractiveVNCController do
  use TuistWeb, :controller

  import Plug.Conn

  alias Tuist.Runners.InteractiveSessions
  alias TuistWeb.RunnerVNCWebSock

  def connect(conn, %{"token" => token}) do
    with {:ok, session} <- InteractiveSessions.validate_token(token),
         :ok <- validate_vnc_session(session) do
      conn
      |> WebSockAdapter.upgrade(RunnerVNCWebSock, %{session: session}, timeout: to_timeout(minute: 65))
      |> halt()
    else
      _ ->
        conn
        |> send_resp(:not_found, "")
        |> halt()
    end
  end

  defp validate_vnc_session(%{kind: :vnc, state: state, relay_host: host, relay_port: port})
       when state in [:ready, :active] and is_binary(host) and host != "" and is_integer(port) and port > 0 and
              port <= 65_535, do: :ok

  defp validate_vnc_session(_session), do: {:error, :not_ready}
end
