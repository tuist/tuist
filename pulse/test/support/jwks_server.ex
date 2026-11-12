defmodule Pulse.Test.JWKSServer do
  @moduledoc false
  # Serves the JWKS held by an Agent (`%{status:, body:}`) and records the
  # authorization header of every request, standing in for an API server.
  @behaviour Plug

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    agent = Keyword.fetch!(opts, :agent)

    %{status: status, body: body} =
      Agent.get_and_update(agent, fn state ->
        {state, Map.update(state, :requests, [], &[get_req_header(conn, "authorization") | &1])}
      end)

    conn |> put_resp_content_type("application/json") |> send_resp(status, body)
  end
end
