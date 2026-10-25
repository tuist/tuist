defmodule TuistWeb.Internal.AtlasFeatureFlagsController do
  @moduledoc false
  use TuistWeb, :controller

  alias Tuist.Ops.FeatureFlags

  def index(conn, _params), do: respond(conn, FeatureFlags.list())
  def evaluate(conn, _params), do: respond(conn, FeatureFlags.evaluate(conn.query_params))
  def show(conn, %{"name" => name}), do: respond(conn, FeatureFlags.get(name))

  def update(conn, %{"name" => name}) do
    respond(conn, FeatureFlags.update(name, conn.body_params, conn.assigns.atlas_principal))
  end

  defp respond(conn, {:ok, result}), do: json(conn, result)

  defp respond(conn, {:error, reason}) do
    status =
      case reason do
        reason when reason in [:unknown_flag, :resource_not_found] -> :not_found
        reason when reason in [:stale_revision, :change_id_conflict] -> :conflict
        :persistence_failed -> :service_unavailable
        _ -> :unprocessable_entity
      end

    conn |> put_status(status) |> json(%{error: Atom.to_string(reason)})
  end
end
