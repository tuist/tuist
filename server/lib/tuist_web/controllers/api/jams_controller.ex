defmodule TuistWeb.API.JamsController do
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Jams
  alias TuistWeb.Authentication

  plug :load_scope
  plug :validate_id

  def index(conn, params) do
    case Jams.list(conn.assigns.app_user, conn.assigns.jam_account, params["cursor"]) do
      {:ok, page} ->
        json(conn, %{
          conn.assigns.jams_collection => Enum.map(page.jams, &Jams.serialize/1),
          :next_cursor => page.next_cursor
        })

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def create(conn, _params),
    do: jam_response(conn, Jams.create(conn.assigns.app_user, conn.assigns.jam_account, conn.body_params))

  def show(conn, params) do
    jam_response(
      conn,
      Jams.get(conn.assigns.app_user, conn.assigns.jam_account, conn.path_params["id"], before: params["before"])
    )
  end

  def message(conn, _params) do
    jam_response(
      conn,
      Jams.message(conn.assigns.app_user, conn.assigns.jam_account, conn.path_params["id"], conn.body_params)
    )
  end

  def update(conn, _params) do
    jam_response(
      conn,
      Jams.archive(
        conn.assigns.app_user,
        conn.assigns.jam_account,
        conn.path_params["id"],
        conn.body_params["status"]
      )
    )
  end

  def repositories(conn, _params) do
    case Jams.repositories(conn.assigns.app_user, conn.assigns.jam_account) do
      {:ok, repositories} -> json(conn, %{repositories: repositories})
      {:error, reason} -> error(conn, reason)
    end
  end

  def models(conn, _params) do
    case Jams.models(conn.assigns.app_user, conn.assigns.jam_account) do
      {:ok, catalog} -> json(conn, catalog)
      {:error, reason} -> error(conn, reason)
    end
  end

  def ship_preview(conn, _params) do
    case Jams.ship_preview(conn.assigns.app_user, conn.assigns.jam_account, conn.path_params["id"]) do
      {:ok, preview} -> json(conn, Map.put(preview, :thread_id, preview.jam_id))
      {:error, reason} -> error(conn, reason)
    end
  end

  def ship(conn, _params) do
    jam_response(
      conn,
      Jams.ship(conn.assigns.app_user, conn.assigns.jam_account, conn.path_params["id"], conn.body_params)
    )
  end

  def reconcile_ship(conn, _params) do
    jam_response(
      conn,
      Jams.reconcile_ship(conn.assigns.app_user, conn.assigns.jam_account, conn.path_params["id"], conn.body_params)
    )
  end

  defp load_scope(conn, _opts) do
    with %User{} = user <- Authentication.app_user(conn) || {:error, :app_required},
         %Account{} = account <- Accounts.get_account_by_handle(conn.path_params["account_handle"]),
         :ok <- Jams.authorize(user, account) do
      conn |> assign(:app_user, user) |> assign(:jam_account, account)
    else
      nil -> conn |> error(:not_found) |> halt()
      {:error, reason} -> conn |> error(reason) |> halt()
    end
  end

  defp validate_id(conn, _opts) do
    case conn.path_params["id"] do
      nil ->
        conn

      id ->
        case Ecto.UUID.cast(id) do
          {:ok, _id} -> conn
          :error -> conn |> error(:not_found) |> halt()
        end
    end
  end

  defp jam_response(conn, {:ok, jam}), do: json(conn, Jams.serialize(jam))
  defp jam_response(conn, {:error, reason}), do: error(conn, reason)

  defp error(conn, :app_required) do
    conn |> put_status(:forbidden) |> json(%{message: "Only a signed-in user can access jams."})
  end

  defp error(conn, reason) when reason in [:not_found, :forbidden, :disabled, :unauthorized] do
    conn |> put_status(:not_found) |> json(%{message: "Not found."})
  end

  defp error(conn, %Ecto.Changeset{}), do: error(conn, :invalid)

  defp error(conn, reason) do
    # Never render upstream errors or changeset values, which may contain prompts or credentials.
    status =
      if reason in [:invalid, :invalid_arguments, :invalid_cursor, :invalid_status, :invalid_request],
        do: :bad_request,
        else: :conflict

    conn |> put_status(status) |> json(%{message: "The jam request could not be completed."})
  end
end
