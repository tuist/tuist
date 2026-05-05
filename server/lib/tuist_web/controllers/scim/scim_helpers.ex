defmodule TuistWeb.SCIM.Helpers do
  @moduledoc """
  Shared response helpers for SCIM 2.0 controllers.
  """
  import Plug.Conn

  alias Tuist.SCIM.Resource

  @content_type "application/scim+json"

  def send_scim_json(conn, status, body) do
    conn
    |> put_resp_content_type(@content_type)
    |> send_resp(status, JSON.encode!(body))
  end

  def send_scim_error(conn, status, detail, scim_type \\ nil) do
    send_scim_json(conn, status, Resource.render_error(status, detail, scim_type))
  end
end
