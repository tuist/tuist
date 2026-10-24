defmodule Atlas.LLMs.PersonalProviders do
  @moduledoc """
  Subscription-account protocols, not OpenAI/Anthropic API-key endpoints.
  Translates the buffered OpenAI tool protocol used by Orbit to Codex Responses
  and Claude Messages. Provider errors are reduced to HTTP status only.
  """

  @timeout :timer.seconds(45)

  def complete("chatgpt", token, params) do
    with {:ok, account_id} <- chatgpt_account_id(token),
         {:ok, body} <-
           request(
             "https://chatgpt.com/backend-api/codex/responses",
             [
               {"authorization", "Bearer " <> token},
               {"chatgpt-account-id", account_id},
               {"openai-beta", "responses=experimental"},
               {"accept", "text/event-stream"}
             ],
             responses_request(params)
           ) do
      responses_completion(body)
    end
  end

  def complete("claude", token, params) do
    with {:ok, body} <-
           request(
             "https://api.anthropic.com/v1/messages",
             [
               {"authorization", "Bearer " <> token},
               {"anthropic-version", "2023-06-01"},
               {"anthropic-beta", "claude-code-20250219,oauth-2025-04-20"},
               {"x-app", "cli"}
             ],
             messages_request(params)
           ) do
      messages_completion(body)
    end
  end

  defp request(url, headers, body) do
    case Req.post(
           url: url,
           headers: headers,
           json: body,
           retry: false,
           redirect: false,
           receive_timeout: @timeout,
           finch: [conn_opts: [transport_opts: [timeout: 5_000]]]
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, status}
      {:error, %{reason: :timeout}} -> {:error, 504}
      {:error, _reason} -> {:error, 502}
    end
  end

  # The token is read only from the owner's encrypted connection. This claim
  # selects the upstream account; it never authenticates an Atlas user.
  defp chatgpt_account_id(token) do
    with [_header, payload, _signature] <- String.split(token, ".", parts: 3),
         {:ok, decoded} <- Base.url_decode64(payload, padding: false),
         {:ok, claims} <- JSON.decode(decoded),
         id when is_binary(id) and byte_size(id) > 0 <-
           get_in(claims, ["https://api.openai.com/auth", "chatgpt_account_id"]) do
      {:ok, id}
    else
      _ -> {:error, 401}
    end
  end

  defp responses_request(params) do
    %{
      "model" => "gpt-5.4",
      # Condukt's buffered chat protocol cannot round-trip opaque reasoning items.
      "reasoning" => %{"effort" => "none"},
      "store" => false,
      "stream" => true,
      "instructions" => system_text(params),
      "input" => Enum.flat_map(conversation(params), &responses_message/1),
      "tools" => Enum.map(params["tools"] || [], &Map.put(&1["function"], "type", "function")),
      "parallel_tool_calls" => true
    }
  end

  defp responses_message(%{"role" => "tool"} = message) do
    [%{"type" => "function_call_output", "call_id" => message["tool_call_id"], "output" => message["content"]}]
  end

  defp responses_message(message) do
    text =
      case message["content"] do
        nil -> []
        "" -> []
        content -> [%{"role" => message["role"], "content" => responses_content(content, message["role"])}]
      end

    calls =
      Enum.map(message["tool_calls"] || [], fn call ->
        Map.merge(call["function"], %{"type" => "function_call", "call_id" => call["id"]})
      end)

    text ++ calls
  end

  defp responses_content(content, _role) when is_binary(content), do: content

  defp responses_content(parts, role) do
    Enum.map(parts, fn
      %{"type" => "image_url", "image_url" => %{"url" => url}} ->
        %{"type" => "input_image", "image_url" => url}

      %{"type" => "text", "text" => text} ->
        %{"type" => if(role == "assistant", do: "output_text", else: "input_text"), "text" => text}
    end)
  end

  # The Codex endpoint requires SSE, but its final event contains the complete
  # output items, including tool IDs/names/arguments. Never use text deltas as a
  # substitute: that silently loses tool calls or accepts truncated streams.
  defp responses_completion(body) when is_binary(body) do
    events = ServerSentEvents.decode_stream([body])

    Enum.find_value(events, {:error, 502}, fn event ->
      case JSON.decode(event.data) do
        {:ok, %{"type" => type, "response" => %{"status" => "completed", "output" => output} = response}}
        when type in ["response.completed", "response.done"] ->
          if Enum.any?(output, &(&1["type"] == "reasoning")),
            do: {:error, 502},
            else: response_items(response, output)

        _ ->
          nil
      end
    end)
  end

  defp responses_completion(_body), do: {:error, 502}

  defp response_items(response, output) do
    text =
      for %{"type" => "message", "content" => parts} <- output,
          %{"type" => "output_text", "text" => text} <- parts,
          do: text

    calls =
      for %{"type" => "function_call"} = item <- output do
        tool_call(item["call_id"], item["name"], item["arguments"])
      end

    completion(response["id"], response["model"], text, calls, response["usage"] || %{})
  end

  defp messages_request(params) do
    %{
      "model" => "claude-sonnet-4-6",
      "max_tokens" => params["max_tokens"] || 2_048,
      "system" => [
        %{"type" => "text", "text" => "You are Claude Code, Anthropic's official CLI for Claude."},
        %{"type" => "text", "text" => system_text(params)}
      ],
      "messages" => Enum.map(conversation(params), &anthropic_message/1),
      "tools" =>
        Enum.map(params["tools"] || [], fn tool ->
          function = tool["function"]

          %{
            "name" => function["name"],
            "description" => function["description"] || "",
            "input_schema" => function["parameters"]
          }
        end)
    }
  end

  defp anthropic_message(%{"role" => "tool"} = message) do
    %{
      "role" => "user",
      "content" => [
        %{"type" => "tool_result", "tool_use_id" => message["tool_call_id"], "content" => message["content"]}
      ]
    }
  end

  defp anthropic_message(message) do
    content = anthropic_content(message["content"])

    calls =
      Enum.map(message["tool_calls"] || [], fn call ->
        %{
          "type" => "tool_use",
          "id" => call["id"],
          "name" => call["function"]["name"],
          "input" => JSON.decode!(call["function"]["arguments"])
        }
      end)

    %{"role" => message["role"], "content" => content ++ calls}
  end

  defp anthropic_content(nil), do: []
  defp anthropic_content(""), do: []
  defp anthropic_content(text) when is_binary(text), do: [%{"type" => "text", "text" => text}]

  defp anthropic_content(parts) do
    Enum.map(parts, fn
      %{"type" => "text"} = part ->
        part

      %{"type" => "image_url", "image_url" => %{"url" => "data:" <> data}} ->
        [media_type, bytes] = String.split(data, ";base64,", parts: 2)
        %{"type" => "image", "source" => %{"type" => "base64", "media_type" => media_type, "data" => bytes}}
    end)
  end

  defp messages_completion(%{"id" => id, "model" => model, "content" => parts} = body) do
    text = for %{"type" => "text", "text" => text} <- parts, do: text

    calls =
      for %{"type" => "tool_use", "id" => id, "name" => name, "input" => input} <- parts do
        tool_call(id, name, JSON.encode!(input))
      end

    completion(id, model, text, calls, body["usage"] || %{})
  end

  defp messages_completion(_body), do: {:error, 502}

  defp completion(id, model, text, calls, usage) do
    message = %{"role" => "assistant", "content" => Enum.join(text, "\n")}
    message = if calls == [], do: message, else: Map.put(message, "tool_calls", calls)

    {:ok,
     %{
       "id" => id,
       "object" => "chat.completion",
       "created" => System.system_time(:second),
       "model" => model,
       "choices" => [
         %{"index" => 0, "message" => message, "finish_reason" => if(calls == [], do: "stop", else: "tool_calls")}
       ],
       "usage" => %{"prompt_tokens" => usage["input_tokens"] || 0, "completion_tokens" => usage["output_tokens"] || 0}
     }}
  end

  defp tool_call(id, name, arguments) do
    %{"id" => id, "type" => "function", "function" => %{"name" => name, "arguments" => arguments}}
  end

  defp conversation(params), do: Enum.reject(params["messages"], &(&1["role"] in ["system", "developer"]))

  defp system_text(params) do
    params["messages"]
    |> Enum.filter(&(&1["role"] in ["system", "developer"]))
    |> Enum.map_join("\n", & &1["content"])
  end
end
