defmodule AtlasWeb.LabelsController do
  use AtlasWeb, :controller

  alias Atlas.Labels

  def image(conn, _) do
    result =
      Labels.request(
        conn.assigns.current_user,
        :image,
        conn.path_params["id"],
        %{"jobId" => conn.path_params["jobId"]},
        "dashboard"
      )

    respond(conn, result)
  end

  def params(conn) do
    if image = conn.path_params["image"] do
      %{"jobId" => String.replace_suffix(image, ".png", "")}
    else
      Map.merge(conn.body_params, Map.take(conn.path_params, ["jobId"]))
    end
  end

  def respond(conn, {:ok, png}) when is_binary(png),
    do:
      conn |> put_resp_header("cache-control", "no-store") |> put_resp_content_type("image/png") |> send_resp(200, png)

  def respond(conn, {:ok, value}), do: conn |> put_resp_header("cache-control", "no-store") |> json(value)

  def respond(conn, {:error, status, message}), do: conn |> put_status(status) |> json(%{error: message})
end
