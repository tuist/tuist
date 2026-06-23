defmodule TuistWeb.Internal.AtlasUsageController do
  @moduledoc """
  Internal Atlas read model endpoints.
  """

  use TuistWeb, :controller

  alias Tuist.Atlas

  def usage(conn, %{"account_handle" => account_handle}) do
    case Atlas.customer_context(account_handle) do
      {:ok, customer_context} ->
        json(conn, customer_context)

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "account_not_found"})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "usage lookup failed"})
    end
  end

  def usage(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "missing account_handle"})
  end
end
