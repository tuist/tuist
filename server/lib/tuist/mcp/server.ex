defmodule Tuist.MCP.Server do
  @moduledoc false

  alias Tuist.MCP.Errors
  alias Tuist.MCP.Prompts
  alias Tuist.MCP.Tools

  @server_info %{
    name: "tuist",
    version: "1.1.0"
  }

  @capabilities %{
    tools: %{listChanged: false},
    prompts: %{listChanged: false}
  }

  def handle_request(%{"method" => method} = request, subject) do
    id = Map.get(request, "id")
    params = Map.get(request, "params", %{})

    if is_nil(id) do
      handle_notification(method, params)
    else
      method
      |> dispatch(params, subject)
      |> build_response(id)
    end
  end

  def handle_request(_request, _subject) do
    build_response(Errors.invalid_request("Invalid request."), nil)
  end

  defp handle_notification("notifications/initialized", _params), do: nil
  defp handle_notification("notifications/" <> _, _params), do: nil
  defp handle_notification(_method, _params), do: nil

  defp dispatch("initialize", _params, _subject) do
    {:ok,
     %{
       protocolVersion: "2025-03-26",
       serverInfo: @server_info,
       capabilities: @capabilities
     }}
  end

  defp dispatch("tools/list", _params, _subject) do
    {:ok, %{tools: Tools.list()}}
  end

  defp dispatch("tools/call", %{"name" => name} = params, subject) do
    arguments = Map.get(params, "arguments", %{})

    case Tools.call(name, arguments, subject) do
      {:ok, content} ->
        {:ok, content}

      {:error, code, message} ->
        {:error, code, message}
    end
  end

  defp dispatch("tools/call", _params, _subject) do
    Errors.invalid_params("Missing required parameter: name.")
  end

  defp dispatch("prompts/list", _params, _subject) do
    {:ok, %{prompts: Prompts.list()}}
  end

  defp dispatch("prompts/get", %{"name" => name} = params, _subject) do
    arguments = Map.get(params, "arguments", %{})

    case Prompts.get(name, arguments) do
      {:ok, result} -> {:ok, result}
      {:error, code, message} -> {:error, code, message}
    end
  end

  defp dispatch("prompts/get", _params, _subject) do
    Errors.invalid_params("Missing required parameter: name.")
  end

  defp dispatch(_method, _params, _subject) do
    Errors.method_not_found()
  end

  defp build_response({:ok, result}, id) do
    %{jsonrpc: "2.0", id: id, result: result}
  end

  defp build_response({:error, code, message}, id) do
    %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}
  end
end
