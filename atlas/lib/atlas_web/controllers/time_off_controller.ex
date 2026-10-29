defmodule AtlasWeb.TimeOffController do
  use AtlasWeb, :controller

  alias Atlas.MCP.Serializers.TimeOff, as: Serializer
  alias Atlas.TimeOff

  plug :no_store

  def index(conn, params) do
    overview =
      TimeOff.overview(conn.assigns.current_user,
        requests_page: params["requests_page"],
        holidays_page: params["holidays_page"]
      )

    json(conn, %{
      requests: Serializer.page(Enum.map(overview.mine, &Serializer.summary/1), overview.mine_meta),
      public_holidays:
        Serializer.page(Enum.map(overview.public_holidays, &Serializer.holiday/1), overview.holidays_meta)
    })
  end

  def create(conn, params) do
    respond(conn, TimeOff.report_holiday(dates(params), conn.assigns.current_user, interface: "api"), :created)
  end

  def update(conn, %{"id" => id} = params) do
    respond(conn, TimeOff.update_holiday(id, dates(params), conn.assigns.current_user, interface: "api"))
  end

  def delete(conn, %{"id" => id}) do
    respond(conn, TimeOff.cancel_holiday(id, conn.assigns.current_user, interface: "api"))
  end

  defp dates(params), do: Map.take(params, ["starts_on", "ends_on"])

  defp respond(conn, result, status \\ :ok)

  defp respond(conn, {:ok, booking}, status),
    do: conn |> put_status(status) |> json(%{request: Serializer.booking(booking)})

  defp respond(conn, {:error, %Ecto.Changeset{}}, _status),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_time_off_dates"})

  defp respond(conn, {:error, _reason}, _status),
    do: conn |> put_status(:not_found) |> json(%{error: "time_off_request_unavailable"})

  defp no_store(conn, _opts), do: put_resp_header(conn, "cache-control", "no-store")
end
