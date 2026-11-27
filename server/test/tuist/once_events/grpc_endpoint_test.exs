defmodule Tuist.OnceEvents.GRPCEndpointTest do
  # Drives the real gRPC listener over HTTP/2, the way a client on the internet
  # reaches it, so these cover the transport and not only the service functions.
  # Not async: the listener's processes use the shared database sandbox.
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.OnceEvents.GRPCEndpoint
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @response_timeout to_timeout(second: 5)

  setup do
    port = free_port()
    options = GRPCEndpoint.server_options(port)
    start_supervised!({GRPC.Server.Supervisor, options})
    %{port: port, max_body_size: options[:max_body_size]}
  end

  test "a stream whose body ends inside a message ends the call", %{port: port} do
    project = ProjectsFixtures.project_fixture()
    headers = [{"authorization", "Bearer " <> Projects.create_project_token(project)}]

    # A length prefix that declares a 100-byte message, then the end of the body.
    # elixir-grpc before 1.1 kept asking for the rest and spun one scheduler for
    # as long as the connection stayed open (CVE-2026-121809).
    assert call(port, "PublishRunEvents", <<0, 100::32>>, headers) ==
             {:ok, Integer.to_string(GRPC.Status.internal())}
  end

  test "a request larger than the body limit is refused before its credentials are checked", %{
    port: port,
    max_body_size: max_body_size
  } do
    # elixir-grpc before 1.0 read a unary body of any size before running
    # interceptors or authentication (CVE-2026-48854).
    length = max_body_size + 1
    body = <<0, length::32>> <> :binary.copy(<<0>>, length)

    assert call(port, "GetArgvHashKey", body, []) ==
             {:ok, Integer.to_string(GRPC.Status.resource_exhausted())}
  end

  defp call(port, rpc, body, headers) do
    {:ok, conn} = Mint.HTTP2.connect(:http, "localhost", port)

    request_headers = [{"content-type", "application/grpc"}, {"te", "trailers"} | headers]

    {:ok, conn, ref} =
      Mint.HTTP2.request(conn, "POST", "/once.events.v1.RunEventService/#{rpc}", request_headers, :stream)

    deadline = System.monotonic_time(:millisecond) + @response_timeout
    state = %{conn: conn, ref: ref, status: nil, done?: false, deadline: deadline}

    state
    |> send_body(body)
    |> await_response()
    |> then(fn
      %{done?: true, status: status, conn: conn} ->
        Mint.HTTP.close(conn)
        {:ok, status}

      %{conn: conn} ->
        Mint.HTTP.close(conn)
        :timeout
    end)
  end

  # Sends the body within the flow-control windows the server grants, and stops
  # early when the server has already answered or reset the stream.
  defp send_body(%{done?: true} = state, _body), do: state
  defp send_body(state, <<>>), do: stream_body(state, :eof)

  defp send_body(state, body) do
    window =
      min(
        Mint.HTTP2.get_window_size(state.conn, :connection),
        Mint.HTTP2.get_window_size(state.conn, {:request, state.ref})
      )

    if window > 0 do
      size = min(window, byte_size(body))
      <<chunk::binary-size(size), rest::binary>> = body
      state |> stream_body(chunk) |> send_body(rest)
    else
      case receive_once(state) do
        {:ok, state} -> send_body(state, body)
        {:timeout, state} -> state
      end
    end
  end

  defp stream_body(state, chunk) do
    case Mint.HTTP2.stream_request_body(state.conn, state.ref, chunk) do
      {:ok, conn} -> %{state | conn: conn}
      {:error, conn, _reason} -> await_response(%{state | conn: conn})
    end
  end

  defp await_response(%{done?: true} = state), do: state

  defp await_response(state) do
    case receive_once(state) do
      {:ok, state} -> await_response(state)
      {:timeout, state} -> state
    end
  end

  defp receive_once(state) do
    remaining = max(state.deadline - System.monotonic_time(:millisecond), 0)

    receive do
      message ->
        case Mint.HTTP2.stream(state.conn, message) do
          {:ok, conn, responses} ->
            {:ok, Enum.reduce(responses, %{state | conn: conn}, &record/2)}

          {:error, conn, _error, responses} ->
            {:ok, Enum.reduce(responses, %{state | conn: conn, done?: true}, &record/2)}

          :unknown ->
            {:ok, state}
        end
    after
      remaining -> {:timeout, state}
    end
  end

  defp record({:headers, ref, headers}, %{ref: ref} = state) do
    case List.keyfind(headers, "grpc-status", 0) do
      {_, status} -> %{state | status: status}
      nil -> state
    end
  end

  defp record({:done, ref}, %{ref: ref} = state), do: %{state | done?: true}
  defp record({:error, ref, _reason}, %{ref: ref} = state), do: %{state | done?: true}
  defp record(_response, state), do: state

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end
