defmodule LuftServerWeb.LoungesController do
  use LuftServerWeb, :controller

  alias LuftServer.Lounges
  alias LuftServer.Tuist.Scope

  plug :load_scope

  def index(conn, _params), do: respond(conn, Lounges.list(conn.assigns.lounge_scope))

  def people(conn, _params) do
    {:ok, people} = Lounges.people(conn.assigns.lounge_scope)
    json(conn, %{people: people})
  end

  def create(conn, _params),
    do: respond(conn, Lounges.create(conn.assigns.lounge_scope, conn.body_params))

  def direct(conn, _params),
    do: respond(conn, Lounges.direct(conn.assigns.lounge_scope, conn.body_params))

  def show(conn, params),
    do:
      respond(
        conn,
        Lounges.get(conn.assigns.lounge_scope, conn.path_params["id"], before: params["before"])
      )

  def message(conn, _params),
    do:
      respond(
        conn,
        Lounges.message(conn.assigns.lounge_scope, conn.path_params["id"], conn.body_params)
      )

  def invite(conn, _params),
    do:
      respond(
        conn,
        Lounges.invite(conn.assigns.lounge_scope, conn.path_params["id"], conn.body_params)
      )

  def read(conn, _params),
    do:
      respond(
        conn,
        Lounges.read(
          conn.assigns.lounge_scope,
          conn.path_params["id"],
          conn.body_params["position"]
        )
      )

  defp load_scope(conn, _opts) do
    case Scope.load(conn.assigns[:session], conn.path_params["account_handle"]) do
      {:ok, scope} -> assign(conn, :lounge_scope, scope)
      {:error, reason} -> conn |> error(reason) |> halt()
    end
  end

  defp respond(conn, {:ok, value}), do: json(conn, value)
  defp respond(conn, {:error, reason}), do: error(conn, reason)

  defp error(conn, reason) when reason in [:not_found, :forbidden] do
    conn |> put_status(:not_found) |> json(%{message: "Not found."})
  end

  defp error(conn, reason) when reason in [:unauthorized, :unauthenticated, :reauthenticate] do
    conn |> put_status(:unauthorized) |> json(%{error: "unauthenticated"})
  end

  defp error(conn, :name_taken) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "name_taken", message: "A lounge with this name already exists."})
  end

  defp error(conn, :invalid_arguments) do
    conn |> put_status(:bad_request) |> json(%{message: "The lounge request is invalid."})
  end

  defp error(conn, :request_conflict) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "request_conflict",
      message: "The lounge request conflicts with an earlier request."
    })
  end

  # Unknown scope errors must never masquerade as absent membership.
  defp error(conn, _reason) do
    conn |> put_status(:bad_gateway) |> json(%{error: "tuist_unavailable"})
  end
end
