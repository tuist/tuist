# Tiny MCP-over-stdio server used by `Condukt.MCP.Transport.Stdio` tests.
#
# Reads newline-delimited JSON-RPC requests from stdin and writes JSON-RPC
# responses to stdout. Implements just enough of the MCP protocol for the
# initialize / tools/list / tools/call exchange.

defmodule EchoMCP do
  @moduledoc false

  def run do
    :io.setopts(:standard_io, binary: true)
    loop()
  end

  defp loop do
    case IO.read(:stdio, :line) do
      :eof ->
        :ok

      data when is_binary(data) ->
        data
        |> String.trim()
        |> handle_line()

        loop()
    end
  end

  defp handle_line(""), do: :ok

  defp handle_line(line) do
    case JSON.decode(line) do
      {:ok, msg} -> handle(msg)
      {:error, _} -> :ok
    end
  end

  defp handle(%{"id" => id, "method" => "initialize"}) do
    respond(id, %{
      "protocolVersion" => "2025-03-26",
      "capabilities" => %{"tools" => %{"listChanged" => false}},
      "serverInfo" => %{"name" => "echo-mcp", "version" => "1.0.0"}
    })
  end

  defp handle(%{"method" => "notifications/initialized"}), do: :ok

  defp handle(%{"id" => id, "method" => "tools/list"}) do
    respond(id, %{
      "tools" => [
        %{
          "name" => "echo",
          "description" => "Echoes back the value it receives.",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{"value" => %{"type" => "string"}},
            "required" => ["value"]
          }
        },
        %{
          "name" => "fail",
          "description" => "Always returns isError: true.",
          "inputSchema" => %{"type" => "object", "properties" => %{}, "required" => []}
        }
      ]
    })
  end

  defp handle(%{
         "id" => id,
         "method" => "tools/call",
         "params" => %{"name" => "echo", "arguments" => %{"value" => value}}
       }) do
    respond(id, %{
      "content" => [%{"type" => "text", "text" => "echo: " <> value}],
      "isError" => false
    })
  end

  defp handle(%{"id" => id, "method" => "tools/call", "params" => %{"name" => "fail"}}) do
    respond(id, %{
      "content" => [%{"type" => "text", "text" => "boom"}],
      "isError" => true
    })
  end

  defp handle(%{"id" => id}) do
    respond_error(id, -32_601, "Method not found")
  end

  defp handle(_), do: :ok

  defp respond(id, result) do
    write(%{"jsonrpc" => "2.0", "id" => id, "result" => result})
  end

  defp respond_error(id, code, message) do
    write(%{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}})
  end

  defp write(envelope) do
    IO.puts(:standard_io, JSON.encode!(envelope))
  end
end

EchoMCP.run()
