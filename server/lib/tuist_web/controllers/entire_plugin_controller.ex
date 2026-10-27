defmodule TuistWeb.EntirePluginController do
  use TuistWeb, :controller

  import TuistWeb.Authentication, only: [require_authenticated_user: 2]

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Entire
  alias Tuist.Entire.Client
  alias Tuist.EntireTrails
  alias Tuist.Environment

  plug :require_authenticated_user

  def start(conn, %{"account_handle" => handle}) do
    with account when not is_nil(account) <- Accounts.get_account_by_handle(handle),
         :ok <- Authorization.authorize(:account_update, conn.assigns.current_user, account),
         true <- EntireTrails.enabled?(account),
         {:ok, state} <- Entire.begin_install(account) do
      callback = Environment.app_url(path: ~p"/integrations/entire/callback")

      conn
      |> put_session(:entire_install, %{state: state, account_id: account.id})
      |> redirect(external: Client.install_url(callback, state))
    else
      _ -> conn |> put_status(:forbidden) |> json(%{error: "Entire installation is not available for this account"})
    end
  end

  def start(conn, _params), do: conn |> put_status(:bad_request) |> json(%{error: "Missing account_handle"})

  def callback(conn, %{"receipt" => receipt, "state" => state}) do
    with %{state: expected, account_id: account_id} <- get_session(conn, :entire_install),
         true <- is_binary(state) and Plug.Crypto.secure_compare(state, expected),
         {:ok, account} <- Accounts.get_account_by_id(account_id),
         :ok <- Authorization.authorize(:account_update, conn.assigns.current_user, account),
         true <- EntireTrails.enabled?(account),
         {:ok, _installation} <- Entire.finish_install(account, state, receipt) do
      conn
      |> delete_session(:entire_install)
      |> redirect(to: ~p"/#{account.name}/settings/integrations")
    else
      {:error, :unavailable} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "Entire is temporarily unavailable"})

      _ ->
        conn |> put_status(:bad_request) |> json(%{error: "Invalid or expired Entire installation"})
    end
  end

  def callback(conn, _params) do
    conn
    |> delete_session(:entire_install)
    |> put_status(:bad_request)
    |> json(%{error: "Entire installation was not completed"})
  end
end
