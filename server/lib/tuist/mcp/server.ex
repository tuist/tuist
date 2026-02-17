defmodule Tuist.MCP.Server do
  @moduledoc false

  use Hermes.Server,
    name: "tuist",
    version: "1.3.0",
    capabilities: [
      {:tools, list_changed?: false},
      {:prompts, list_changed?: false}
    ],
    protocol_versions: ["2025-03-26"]

  alias Hermes.MCP.Error
  alias Hermes.Server.Component.Prompt
  alias Hermes.Server.Component.Tool
  alias Hermes.Server.Frame
  alias Hermes.Server.Handlers
  alias Tuist.MCP.Components.Prompts.FixFlakyTest
  alias Tuist.MCP.Components.Tools.GetTestCase
  alias Tuist.MCP.Components.Tools.GetTestCaseRun
  alias Tuist.MCP.Components.Tools.GetTestRun
  alias Tuist.MCP.Components.Tools.ListProjects
  alias Tuist.MCP.Components.Tools.ListTestCases

  component ListProjects, name: "list_projects"
  component ListTestCases, name: "list_test_cases"
  component GetTestCase, name: "get_test_case"
  component GetTestRun, name: "get_test_run"
  component GetTestCaseRun, name: "get_test_case_run"
  component FixFlakyTest, name: "fix_flaky_test"

  @impl Hermes.Server
  def handle_request(%{"method" => "initialize"}, %Frame{} = frame) do
    {:reply,
     %{
       protocolVersion: hd(supported_protocol_versions()),
       serverInfo: atomize_keys(server_info()),
       capabilities: atomize_keys(server_capabilities())
     }, frame}
  end

  @impl Hermes.Server
  def handle_request(
        %{"method" => "tools/call", "params" => %{"name" => _name} = params} = request,
        %Frame{} = frame
      ) do
    request = put_in(request, ["params"], Map.put_new(params, "arguments", %{}))
    Handlers.handle(request, __MODULE__, frame)
  end

  @impl Hermes.Server
  def handle_request(%{"method" => "tools/call"}, %Frame{} = frame) do
    {:error, invalid_params_error("Missing required parameter: name."), frame}
  end

  @impl Hermes.Server
  def handle_request(
        %{"method" => "prompts/get", "params" => %{"name" => _name} = params} = request,
        %Frame{} = frame
      ) do
    request = put_in(request, ["params"], Map.put_new(params, "arguments", %{}))
    Handlers.handle(request, __MODULE__, frame)
  end

  @impl Hermes.Server
  def handle_request(%{"method" => "prompts/get"}, %Frame{} = frame) do
    {:error, invalid_params_error("Missing required parameter: name."), frame}
  end

  @impl Hermes.Server
  def handle_request(%{"method" => method} = request, %Frame{} = frame)
      when method in ["tools/list", "prompts/list"] do
    Handlers.handle(request, __MODULE__, frame)
  end

  @impl Hermes.Server
  def handle_request(%{"method" => _method}, %Frame{} = frame) do
    {:error, %Error{code: -32_601, reason: :method_not_found, message: "Method not found.", data: %{}}, frame}
  end

  def handle_request(%{"method" => method} = request, subject) when not is_struct(subject, Frame) do
    id = Map.get(request, "id")
    params = Map.get(request, "params", %{})

    if is_nil(id) do
      handle_client_notification(method, params)
    else
      frame = Frame.new() |> Frame.assign(current_subject: subject)
      hermes_request = %{"method" => method, "params" => params}

      case handle_request(hermes_request, frame) do
        {:reply, result, _frame} ->
          %{jsonrpc: "2.0", id: id, result: atomize_keys(result)}

        {:error, %Error{} = error, _frame} ->
          %{jsonrpc: "2.0", id: id, error: build_error(error)}

        {:noreply, _frame} ->
          nil
      end
    end
  end

  def handle_request(_request, _subject) do
    %{jsonrpc: "2.0", id: nil, error: %{code: -32_600, message: "Invalid request."}}
  end

  @impl Hermes.Server
  def handle_notification(_notification, %Frame{} = frame), do: {:noreply, frame}

  defp handle_client_notification("notifications/initialized", _params), do: nil
  defp handle_client_notification("notifications/" <> _, _params), do: nil
  defp handle_client_notification(_method, _params), do: nil

  defp build_error(%Error{} = error) do
    data_message = Map.get(error.data, :message) || Map.get(error.data, "message")
    message = resolve_error_message(error, data_message)

    %{code: error.code, message: message}
  end

  defp resolve_error_message(%Error{code: -32_602, message: "Invalid params"}, "Tool not found: " <> name) do
    "Unknown tool: #{name}"
  end

  defp resolve_error_message(%Error{code: -32_602, message: "Invalid params"}, "Prompt not found: " <> name) do
    "Unknown prompt: #{name}"
  end

  defp resolve_error_message(%Error{code: -32_602, message: "Invalid params"}, data_message)
       when is_binary(data_message) do
    data_message
  end

  defp resolve_error_message(%Error{message: nil, reason: reason}, _data_message),
    do: fallback_message(reason)

  defp resolve_error_message(%Error{message: message}, _data_message), do: message

  defp fallback_message(:invalid_request), do: "Invalid request."
  defp fallback_message(:method_not_found), do: "Method not found."
  defp fallback_message(:invalid_params), do: "Invalid params"
  defp fallback_message(:internal_error), do: "Internal error"
  defp fallback_message(_), do: "Server error"

  defp invalid_params_error(message) do
    %Error{code: -32_602, reason: :invalid_params, message: message, data: %{}}
  end

  defp atomize_keys(%Tool{} = tool) do
    %{
      name: tool.name,
      description: tool.description,
      inputSchema: atomize_keys(tool.input_schema)
    }
    |> maybe_put(:title, tool.title)
    |> maybe_put(:outputSchema, atomize_keys(tool.output_schema))
    |> maybe_put(:annotations, atomize_keys(tool.annotations))
  end

  defp atomize_keys(%Prompt{} = prompt) do
    %{
      name: prompt.name,
      description: prompt.description,
      arguments: atomize_keys(prompt.arguments)
    }
  end

  defp atomize_keys(%_{} = struct), do: struct

  defp atomize_keys(%{} = map) do
    map
    |> Enum.map(fn {key, value} ->
      atom_key = if is_binary(key), do: String.to_atom(key), else: key
      {atom_key, atomize_keys(value)}
    end)
    |> Map.new()
  end

  defp atomize_keys(list) when is_list(list), do: Enum.map(list, &atomize_keys/1)
  defp atomize_keys(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
