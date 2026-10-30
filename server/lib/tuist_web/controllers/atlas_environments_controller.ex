defmodule TuistWeb.AtlasEnvironmentsController do
  @moduledoc false
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Sandboxes.AtlasIdentity
  alias Tuist.Sandboxes.ProviderEnvironments

  def start(conn, params), do: dispatch(conn, params, :start)
  def exec(conn, params), do: dispatch(conn, params, :exec)
  def pause(conn, params), do: dispatch(conn, params, :pause)
  def delete(conn, params), do: dispatch(conn, params, :delete)

  defp dispatch(conn, %{"account_handle" => handle, "environment_id" => id}, operation) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, key} <- AtlasIdentity.verify(token, handle, id),
         account when not is_nil(account) <- Accounts.get_account_by_handle(handle) do
      case ProviderEnvironments.dispatch(account, key, operation, conn.body_params) do
        {:ok, payload} -> json(conn, payload)
        {:error, :invalid_params} -> conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_params"})
        {:error, :stale_generation} -> conn |> put_status(:conflict) |> json(%{error: "stale_generation"})
        {:error, :disabled} -> conn |> put_status(:forbidden) |> json(%{error: "disabled"})
        _ -> conn |> put_status(:service_unavailable) |> json(%{error: "environment_unavailable"})
      end
    else
      _ -> conn |> put_status(:unauthorized) |> json(%{error: "invalid_identity"})
    end
  end
end
