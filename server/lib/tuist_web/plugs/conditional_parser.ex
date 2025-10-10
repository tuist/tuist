defmodule TuistWeb.Plugs.ConditionalParser do
  @moduledoc """
  A plug that conditionally applies body parsing based on the request path and content type.
  
  This plug skips parsing for binary upload endpoints like CAS artifacts to avoid
  body read timeouts when the parser tries to parse binary data as structured data.
  """
  
  import Plug.Conn
  
  def init(_opts), do: []
  
  def call(conn, _opts) do
    if should_skip_parsing?(conn) do
      # Skip parsing for binary uploads
      conn
    else
      # Apply normal parsing for other requests
      Plug.Parsers.call(conn, parser_opts())
    end
  end
  
  # Skip parsing for CAS upload endpoints with binary content
  defp should_skip_parsing?(conn) do
    content_type = get_req_header(conn, "content-type") |> List.first()
    path = conn.request_path
    
    case {path, content_type} do
      {"/api/cas/" <> _, "application/octet-stream"} -> true
      _ -> false
    end
  end
  
  defp parser_opts do
    Plug.Parsers.init(
      parsers: [:urlencoded, :multipart, :json],
      pass: ["*/*"],
      json_decoder: Phoenix.json_library()
    )
  end
end