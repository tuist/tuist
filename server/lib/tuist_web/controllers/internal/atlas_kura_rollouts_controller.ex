defmodule TuistWeb.Internal.AtlasKuraRolloutsController do
  @moduledoc false
  use TuistWeb, :controller

  alias Tuist.Ops.KuraRollouts

  def show(conn, params) do
    case KuraRollouts.get(params["id"]) do
      {:ok, result} -> json(conn, result)
      {:error, :resource_not_found} -> conn |> put_status(:not_found) |> json(%{error: "resource_not_found"})
    end
  end
end
