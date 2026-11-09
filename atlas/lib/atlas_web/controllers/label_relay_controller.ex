defmodule AtlasWeb.LabelRelayController do
  use AtlasWeb, :controller

  alias Atlas.Labels
  alias AtlasWeb.LabelsController

  def action(conn, _) do
    token =
      case get_req_header(conn, "authorization") do
        ["Bearer " <> token] -> token
        _ -> ""
      end

    data = LabelsController.params(conn)
    result = Labels.relay(action_name(conn), conn.path_params["id"], token, data)
    LabelsController.respond(put_resp_header(conn, "cache-control", "no-store"), result)
  end
end
