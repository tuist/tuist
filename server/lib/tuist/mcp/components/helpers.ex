defmodule Tuist.MCP.Components.Helpers do
  @moduledoc false

  alias Hermes.MCP.Error
  alias Hermes.Server.Frame
  alias Hermes.Server.Response

  @spec to_tool_response(term(), Frame.t()) ::
          {:reply, Response.t(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def to_tool_response({:ok, %{content: content}}, frame) when is_list(content) do
    {:reply, build_tool_response(content), frame}
  end

  def to_tool_response({:ok, %{"content" => content}}, frame) when is_list(content) do
    {:reply, build_tool_response(content), frame}
  end

  def to_tool_response({:error, code, message}, frame) when is_integer(code) and is_binary(message) do
    {:error, legacy_error(code, message), frame}
  end

  def to_tool_response(_unexpected, frame) do
    {:error, Error.execution("Unexpected MCP tool result."), frame}
  end

  @spec normalize_legacy_arguments(term()) :: term()
  def normalize_legacy_arguments(%{} = map) do
    map
    |> Enum.map(fn {key, value} -> {normalize_argument_key(key), normalize_legacy_arguments(value)} end)
    |> Map.new()
  end

  def normalize_legacy_arguments(list) when is_list(list),
    do: Enum.map(list, &normalize_legacy_arguments/1)

  def normalize_legacy_arguments(value), do: value

  @spec to_prompt_response(term(), Frame.t()) ::
          {:reply, Response.t(), Frame.t()} | {:error, Error.t(), Frame.t()}
  def to_prompt_response({:ok, %{messages: messages}}, frame) when is_list(messages) do
    {:reply, build_prompt_response(messages), frame}
  end

  def to_prompt_response({:ok, %{"messages" => messages}}, frame) when is_list(messages) do
    {:reply, build_prompt_response(messages), frame}
  end

  def to_prompt_response({:error, code, message}, frame) when is_integer(code) and is_binary(message) do
    {:error, legacy_error(code, message), frame}
  end

  def to_prompt_response(_unexpected, frame) do
    {:error, Error.execution("Unexpected MCP prompt result."), frame}
  end

  defp build_tool_response(content) do
    Enum.reduce(content, Response.tool(), &append_content/2)
  end

  defp append_content(%{"type" => "text", "text" => text}, response) when is_binary(text) do
    Response.text(response, text)
  end

  defp append_content(%{type: "text", text: text}, response) when is_binary(text) do
    Response.text(response, text)
  end

  defp append_content(_item, response), do: response

  defp build_prompt_response(messages) do
    %Response{} = prompt_response = Response.prompt()
    %Response{prompt_response | messages: Enum.map(messages, &stringify_keys/1)}
  end

  defp stringify_keys(%{} = map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), stringify_keys(value)} end)
    |> Map.new()
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp normalize_argument_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_argument_key(key), do: key

  defp legacy_error(code, message) do
    %Error{code: code, reason: reason_for_code(code), message: message, data: %{}}
  end

  defp reason_for_code(-32_600), do: :invalid_request
  defp reason_for_code(-32_601), do: :method_not_found
  defp reason_for_code(-32_602), do: :invalid_params
  defp reason_for_code(-32_603), do: :internal_error
  defp reason_for_code(_), do: :execution_error
end
