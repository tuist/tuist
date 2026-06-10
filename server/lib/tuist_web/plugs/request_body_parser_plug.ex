defmodule TuistWeb.Plugs.RequestBodyParserPlug do
  @moduledoc """
  Wraps `Plug.Parsers` so request body timeouts become client-facing 408s.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(options) do
    Plug.Parsers.init(options)
  end

  @impl true
  def call(conn, parser_opts) do
    Plug.Parsers.call(conn, parser_opts)
  rescue
    error in Bandit.HTTPError ->
      if error.plug_status == :request_timeout do
        conn
        |> send_resp(408, "Request Timeout")
        |> halt()
      else
        reraise error, __STACKTRACE__
      end
  end
end
