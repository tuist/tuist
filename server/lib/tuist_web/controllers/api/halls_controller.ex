defmodule TuistWeb.API.HallsController do
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Halls
  alias TuistWeb.Authentication

  plug :load_scope

  def index(conn, _params), do: respond(conn, Halls.list(conn.assigns.app_user, conn.assigns.hall_account))

  def people(conn, _params) do
    case Halls.people(conn.assigns.app_user, conn.assigns.hall_account) do
      {:ok, people} -> json(conn, %{people: people})
      {:error, reason} -> error(conn, reason)
    end
  end

  def create(conn, _params),
    do: respond(conn, Halls.create(conn.assigns.app_user, conn.assigns.hall_account, conn.body_params))

  def direct(conn, _params),
    do: respond(conn, Halls.direct(conn.assigns.app_user, conn.assigns.hall_account, conn.body_params))

  def show(conn, params) do
    respond(
      conn,
      Halls.get(conn.assigns.app_user, conn.assigns.hall_account, conn.path_params["id"], before: params["before"])
    )
  end

  def message(conn, _params) do
    respond(
      conn,
      Halls.message(conn.assigns.app_user, conn.assigns.hall_account, conn.path_params["id"], conn.body_params)
    )
  end

  def invite(conn, _params) do
    respond(
      conn,
      Halls.invite(conn.assigns.app_user, conn.assigns.hall_account, conn.path_params["id"], conn.body_params)
    )
  end

  def read(conn, _params) do
    respond(
      conn,
      Halls.read(
        conn.assigns.app_user,
        conn.assigns.hall_account,
        conn.path_params["id"],
        conn.body_params["position"]
      )
    )
  end

  defp load_scope(conn, _opts) do
    with %User{} = user <- Authentication.app_user(conn) || {:error, :app_required},
         %Account{} = account <- Accounts.get_account_by_handle(conn.path_params["account_handle"]),
         :ok <- Halls.authorize(user, account) do
      conn |> assign(:app_user, user) |> assign(:hall_account, account)
    else
      nil -> conn |> error(:not_found) |> halt()
      {:error, reason} -> conn |> error(reason) |> halt()
    end
  end

  defp respond(conn, {:ok, value}), do: json(conn, value)
  defp respond(conn, {:error, reason}), do: error(conn, reason)

  defp error(conn, :app_required) do
    conn |> put_status(:forbidden) |> json(%{message: "Only a signed-in user can access halls."})
  end

  # Missing flags, membership and halls look the same, so a hall's existence
  # never leaks to someone who can't read it.
  defp error(conn, reason) when reason in [:not_found, :forbidden] do
    conn |> put_status(:not_found) |> json(%{message: "Not found."})
  end

  defp error(conn, :name_taken) do
    conn |> put_status(:conflict) |> json(%{code: "name_taken", message: "A hall with this name already exists."})
  end

  defp error(conn, :invalid_arguments) do
    conn |> put_status(:bad_request) |> json(%{message: "The hall request is invalid."})
  end

  defp error(conn, _reason) do
    # Never render changeset values, which contain messages.
    conn |> put_status(:conflict) |> json(%{message: "The hall request could not be completed."})
  end
end
