defmodule Pulse.Test.CollectorBridgeTap do
  @moduledoc "Loopback-only capture/failure proxy for controlled tiny Collector interoperability payloads."
  @behaviour Plug

  import Plug.Conn

  alias PulseWeb.OTLPHTTP

  def init(opts), do: opts

  def call(conn, opts) do
    agent = Keyword.fetch!(opts, :agent)
    {:ok, body, conn} = read_body(conn, length: 65_536)
    [tenant] = get_req_header(conn, "x-scope-orgid")

    reservation = Agent.get_and_update(agent, &reserve(&1, tenant))

    {failure, owner} =
      case reservation do
        :limit -> raise "bridge request evidence limit exceeded"
        pair -> pair
      end

    {conn, response_body} =
      if failure do
        {conn |> put_resp_header("retry-after", "1") |> OTLPHTTP.error(failure, "owned bridge retry fixture"), nil}
      else
        target = Map.fetch!(Keyword.fetch!(opts, :targets), tenant)

        headers =
          Enum.filter(conn.req_headers, fn {name, _} ->
            name in ["authorization", "x-scope-orgid", "content-type", "content-encoding"]
          end)

        response = Req.post!(target <> "/v1/traces", headers: headers, body: body, retry: false, decode_body: false)
        [type] = response.headers["content-type"]
        {conn |> put_resp_content_type(type, nil) |> send_resp(response.status, response.body), response.body}
      end

    entry = %{
      tenant: tenant,
      status: conn.status,
      headers: conn.req_headers,
      body: body,
      response: response_body,
      time: System.monotonic_time(:millisecond)
    }

    Agent.update(agent, fn state -> %{state | requests: [entry | state.requests]} end)
    send(owner, {:collector_request, entry})
    conn
  end

  defp reserve(state, tenant) do
    count = Map.get(state, :count, 0) + 1

    if count > 64 do
      {:limit, state}
    else
      state = Map.put(state, :count, count)

      {failure, rest} =
        case Map.get(state.failures, tenant, []) do
          [status | rest] -> {status, rest}
          [] -> {nil, []}
        end

      {{failure, state.owner}, %{state | failures: Map.put(state.failures, tenant, rest)}}
    end
  end
end
