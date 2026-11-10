defmodule TuistWeb.SandboxAllocationsController do
  use TuistWeb, :controller

  alias Tuist.Sandboxes
  alias TuistWeb.RunnerControllerAuth

  def update(conn, params) do
    with :ok <- RunnerControllerAuth.authenticate(conn),
         :ok <- Sandboxes.update_allocation(params) do
      send_resp(conn, :no_content, "")
    else
      {:error, :invalid_allocation} -> conn |> put_status(:bad_request) |> json(%{error: "invalid allocation"})
      {:error, :stale_allocation} -> conn |> put_status(:conflict) |> json(%{error: "stale allocation"})
      {:error, :not_in_cluster} -> conn |> put_status(:service_unavailable) |> json(%{error: "kubernetes unavailable"})
      {:error, _reason} -> conn |> put_status(:unauthorized) |> json(%{error: "invalid controller token"})
    end
  end
end
