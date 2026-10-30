defmodule AtlasWeb.CodingRepositoriesController do
  use AtlasWeb, :controller

  alias Atlas.Audit
  alias Atlas.CodingRepositories

  def index(conn, params) do
    audited(conn, fn ->
      if Map.keys(params) -- ["installation_id"] == [],
        do: CodingRepositories.catalog(conn.assigns.current_user, Map.get(params, "installation_id", :saved)),
        else: {:error, :invalid_params}
    end)
  end

  def update(conn, _params),
    do: audited(conn, fn -> CodingRepositories.update(conn.assigns.current_user, conn.body_params) end)

  defp audited(conn, action) do
    result = Audit.with_context(%{actor: conn.assigns.current_user, interface: "api"}, action)

    case result do
      {:ok, payload} ->
        json(conn, payload)

      {:error, reason} ->
        status = if reason == :invalid_params, do: 422, else: 409
        conn |> put_status(status) |> json(%{error: Atom.to_string(reason)})
    end
  end
end
