defmodule TuistLabelsWeb.API do
  use Phoenix.Controller, formats: [:json]
  alias TuistLabels.Store

  def health(conn, _), do: json(conn, %{ok: true})
  def create(conn, _), do: respond(conn, Store.request({:create, conn.remote_ip}), 201)

  def action(%{private: %{phoenix_action: action}} = conn, _) when action in [:health, :create],
    do: apply(__MODULE__, action, [conn, conn.params])

  def action(conn, _) do
    operation = Phoenix.Controller.action_name(conn)

    [credential] =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] -> [token]
        _ -> [""]
      end

    data =
      case operation do
        :status -> false
        :image -> String.replace_suffix(conn.path_params["image"], ".png", "")
        _ -> Map.merge(conn.body_params, Map.take(conn.path_params, ["jobId"]))
      end

    result = Store.request({operation, conn.path_params["id"], credential, data})

    case {operation, result} do
      {:image, {:ok, png}} -> conn |> put_resp_content_type("image/png") |> send_resp(200, png)
      _ -> respond(conn, result, if(operation == :submit, do: 201, else: 200))
    end
  end

  defp respond(conn, {:ok, value}, status), do: conn |> put_status(status) |> json(value)

  defp respond(conn, {:error, status, message}, _),
    do: conn |> put_status(status) |> json(%{error: message})
end
