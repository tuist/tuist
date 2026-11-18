defmodule Condukt.Session.Translate do
  @moduledoc """
  Converts between Condukt's conversation types and ReqLLM's.

  This is the whole of Condukt's knowledge of what a provider request looks
  like, and it is the reason the rest of the session does not have to know. It
  lived inside `Condukt.Session` alongside the process, the agent loop, tool
  dispatch and persistence, where it was the largest block in the file and the
  one most obviously unrelated to running a GenServer.

  Every function here takes what it needs rather than a session struct, so
  nothing in this module can reach into session state and none of it needs a
  session to be tested.
  """

  alias Condukt.Message
  alias Condukt.Redactor
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.ToolCall

  @doc """
  Builds the context sent to a provider.

  Redactors run on the way out, so nothing a redactor removes can reach the
  provider even though the session keeps it in history.
  """
  def context(messages, redactors, system_prompt) do
    context_messages =
      redactors
      |> Redactor.redact_messages(messages)
      |> Enum.map(&message_to_req_llm/1)
      |> List.flatten()

    if system_prompt do
      ReqLLM.Context.new([ReqLLM.Context.system(system_prompt) | context_messages])
    else
      ReqLLM.Context.new(context_messages)
    end
  end

  @doc "Translates a Condukt message into the shape ReqLLM expects."
  def message_to_req_llm(%Message{role: :user, content: content, images: []}) do
    ReqLLM.Context.user(content)
  end

  def message_to_req_llm(%Message{role: :user, content: content, images: images}) when images != [] do
    # ReqLLM represents multi-part user content as a list of content parts:
    # the text, then one image part per attachment as a base64 data URL.
    image_parts =
      Enum.map(images, fn image ->
        ContentPart.image_url("data:#{image.media_type};base64,#{image.data}")
      end)

    ReqLLM.Context.user([ContentPart.text(content) | image_parts])
  end

  def message_to_req_llm(%Message{role: :assistant, content: content}) when is_binary(content) do
    ReqLLM.Context.assistant(content)
  end

  def message_to_req_llm(%Message{role: :assistant, content: blocks}) when is_list(blocks) do
    text =
      blocks
      |> Enum.filter(&match?({:text, _}, &1))
      |> Enum.map_join("", fn {:text, chunk} -> chunk end)

    tool_calls =
      blocks
      |> Enum.filter(&match?({:tool_call, _, _, _}, &1))
      |> Enum.map(fn {:tool_call, id, name, arguments} ->
        %{id: id, name: name, arguments: arguments}
      end)

    message = ReqLLM.Context.assistant(text, tool_calls: tool_calls)
    details = for {:reasoning_details, details} <- blocks, detail <- details, do: detail
    %{message | reasoning_details: if(details != [], do: details)}
  end

  def message_to_req_llm(%Message{role: :tool_result, tool_call_id: id, content: content}) do
    ReqLLM.Context.tool_result(id, encode_tool_result(content))
  end

  @doc "Renders a tool result as provider text, also used for context accounting."
  def encode_tool_result(content) when is_binary(content), do: content
  def encode_tool_result({:error, reason}), do: "Error: #{inspect(reason)}"
  def encode_tool_result(content), do: JSON.encode!(content)

  @doc """
  Turns a provider response into an assistant message.

  Thinking, text, and tool calls become ordered content blocks. A response with
  none of them still produces a message, because an empty assistant turn is
  part of the conversation and dropping it would leave the history unable to
  explain itself.
  """
  def response_to_message(response) do
    blocks =
      block(:reasoning_details, response.message.reasoning_details) ++
        block(:thinking, ReqLLM.Response.thinking(response)) ++
        block(:text, ReqLLM.Response.text(response)) ++
        tool_call_blocks(response)

    if blocks == [], do: Message.assistant(""), else: Message.assistant(blocks)
  end

  defp block(_kind, nil), do: []
  defp block(_kind, ""), do: []
  defp block(_kind, []), do: []
  defp block(kind, content), do: [{kind, content}]

  defp tool_call_blocks(response) do
    response
    |> ReqLLM.Response.tool_calls()
    |> Enum.map(fn call ->
      normalized = ToolCall.from_map(call)
      {:tool_call, normalized.id, normalized.name, normalized.arguments}
    end)
  end

  @doc """
  Builds the provider options for one call.

  `config` carries `:api_key`, `:base_url`, `:thinking_level`, `:max_tokens`,
  and optional `:request_options`; each configured value is omitted when unset
  so a provider's own default applies. `trace_headers` are merged into the
  caller's Req options, including existing request headers.
  """
  def llm_opts(config, tools, trace_headers \\ []) do
    config
    |> Keyword.get(:request_options)
    |> Kernel.||([])
    |> put_present(:api_key, config[:api_key])
    |> put_present(:base_url, config[:base_url])
    |> put_present(:max_tokens, config[:max_tokens])
    |> put_tools(tools)
    |> put_reasoning(config[:thinking_level])
    |> merge_trace_headers(trace_headers)
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)

  defp put_tools(opts, []), do: opts
  defp put_tools(opts, tools), do: Keyword.put(opts, :tools, tools)

  defp put_reasoning(opts, :off), do: Keyword.put(opts, :reasoning_effort, :none)

  defp put_reasoning(opts, level) when level in [:minimal, :low, :medium, :high] do
    Keyword.put(opts, :reasoning_effort, level)
  end

  defp put_reasoning(opts, _level), do: opts

  defp merge_trace_headers(opts, []), do: opts

  defp merge_trace_headers(opts, trace_headers) do
    http_opts = Keyword.get(opts, :req_http_options, [])
    headers = merge_headers(Keyword.get(http_opts, :headers, []), trace_headers)

    opts
    |> Keyword.put(:req_http_options, Keyword.put(http_opts, :headers, headers))
  end

  defp merge_headers(headers, trace_headers) do
    trace_headers
    |> Enum.reduce(normalize_headers(headers), fn {name, value}, acc ->
      case String.downcase(name) do
        "baggage" -> put_header(acc, name, merge_baggage(header_value(acc, name), value))
        _ -> put_header(acc, name, value)
      end
    end)
  end

  defp normalize_headers(headers) when is_map(headers), do: normalize_headers(Map.to_list(headers))

  defp normalize_headers(headers) when is_list(headers) do
    Enum.flat_map(headers, &normalize_header/1)
  end

  defp normalize_headers(_headers), do: []

  defp normalize_header({name, values}) when is_list(values) do
    if Enum.all?(values, &is_binary/1) do
      Enum.map(values, &{to_string(name), &1})
    else
      [{to_string(name), to_string(values)}]
    end
  end

  defp normalize_header({name, value}) when is_binary(value), do: [{to_string(name), value}]
  defp normalize_header({name, value}), do: [{to_string(name), to_string(value)}]
  defp normalize_header(_header), do: []

  defp put_header(headers, name, value) do
    [{name, value} | Enum.reject(headers, &(String.downcase(elem(&1, 0)) == String.downcase(name)))]
  end

  defp header_value(headers, wanted) do
    Enum.find_value(headers, fn {name, value} -> if String.downcase(name) == String.downcase(wanted), do: value end)
  end

  defp merge_baggage(nil, trace_baggage), do: trace_baggage
  defp merge_baggage("", trace_baggage), do: trace_baggage

  defp merge_baggage(user_baggage, trace_baggage) do
    user_baggage = without_baggage_key(user_baggage, "condukt.session.id")

    trace_baggage
    |> without_baggage_keys(baggage_keys(user_baggage))
    |> case do
      "" -> user_baggage
      nil -> user_baggage
      baggage when user_baggage == "" -> baggage
      baggage -> user_baggage <> "," <> baggage
    end
  end

  defp without_baggage_key(baggage, key) do
    without_baggage_keys(baggage, [key])
  end

  defp without_baggage_keys(nil, _keys), do: nil

  defp without_baggage_keys(baggage, keys) do
    baggage
    |> String.split(",", trim: true)
    |> Enum.reject(&(baggage_key(&1) in keys))
    |> Enum.join(",")
  end

  defp baggage_keys(nil), do: []

  defp baggage_keys(baggage) do
    baggage
    |> String.split(",", trim: true)
    |> Enum.map(&baggage_key/1)
  end

  defp baggage_key(item) do
    item
    |> String.split(";", parts: 2)
    |> hd()
    |> String.split("=", parts: 2)
    |> hd()
    |> String.trim()
    |> String.downcase()
  end

  @doc """
  Normalizes a JSON Schema so its keys are strings.

  Schemas arrive written either way, and a provider that receives atom keys
  rejects the request rather than coercing them.
  """
  def normalize_json_schema(schema) when is_map(schema) do
    Map.new(schema, fn {key, value} -> {to_string(key), normalize_json_schema(value)} end)
  end

  def normalize_json_schema(schema) when is_list(schema), do: Enum.map(schema, &normalize_json_schema/1)
  def normalize_json_schema(value), do: value

  @doc "A model reference as a string, for telemetry metadata."
  def model_identifier(model) when is_binary(model), do: model
  def model_identifier(model), do: inspect(model)
end
