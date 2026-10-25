defmodule Atlas.LLMs.PersonalProviders do
  @moduledoc """
  Subscription-account protocols, not OpenAI/Anthropic API-key endpoints.
  Translates the buffered OpenAI tool protocol used by Orbit to Codex Responses
  and Claude Messages. Provider errors return only sanitized HTTP statuses;
  diagnostics contain fixed categories, never upstream messages or bodies.
  """

  alias OpenTelemetry.Tracer

  require Logger

  @timeout :timer.seconds(45)

  def complete("chatgpt", token, params) do
    result =
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

    report_result("chatgpt", result)
  end

  def complete("claude", token, params) do
    result =
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

    report_result("claude", result)
  end

  defp report_result(provider, {:error, status, category}) do
    Tracer.add_event("orbit.personal_provider.failed", %{
      "provider" => provider,
      "status" => status,
      "category" => Atom.to_string(category)
    })

    Logger.warning("Orbit personal provider failed: provider=#{provider} category=#{category} status=#{status}")
    {:error, status}
  end

  defp report_result(_provider, result), do: result

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
      {:ok, %{status: status}} -> {:error, status, :http_error}
      {:error, %{reason: :timeout}} -> {:error, 504, :timeout}
      {:error, _reason} -> {:error, 502, :request_failed}
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
      _ -> {:error, 401, :invalid_account_claim}
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

  # Codex can deliver complete items separately from a metadata-only terminal.
  # Never substitute deltas or accept done items without successful completion:
  # that silently loses tool calls or accepts truncated streams.
  defp responses_completion(body) when is_binary(body) do
    result =
      body
      |> then(&ServerSentEvents.decode_stream([&1]))
      |> Enum.reduce_while([], fn event, output ->
        case JSON.decode(event.data) do
          {:ok, event} -> responses_event(event, output)
          _ -> {:cont, output}
        end
      end)

    case result do
      output when is_list(output) -> {:error, 502, :incomplete_stream}
      result -> result
    end
  end

  defp responses_completion(_body), do: {:error, 502, :invalid_response}

  defp responses_event(%{"type" => "response.output_item.done", "item" => item}, output) when is_map(item),
    do: {:cont, [item | output]}

  defp responses_event(%{"type" => type, "response" => response}, output)
       when type in ["response.completed", "response.done"] and is_map(response) do
    {:halt, completed_response(response, output)}
  end

  defp responses_event(%{"type" => "response.failed", "response" => %{"error" => error}}, _output),
    do: {:halt, upstream_error(error)}

  defp responses_event(%{"type" => "error"} = event, _output), do: {:halt, upstream_error(event["error"] || event)}

  defp responses_event(%{"type" => "response.incomplete"}, _output), do: {:halt, {:error, 502, :incomplete_response}}

  defp responses_event(%{"type" => type}, _output)
       when type in ["response.completed", "response.done", "response.failed"],
       do: {:halt, {:error, 502, :invalid_response}}

  defp responses_event(_event, output), do: {:cont, output}

  defp completed_response(response, output) do
    cond do
      response["status"] not in [nil, "completed"] -> {:error, 502, :invalid_response}
      Enum.any?(output, &unsupported_reasoning?/1) -> {:error, 502, :unsupported_reasoning}
      is_list(response["output"]) -> response_items(response, response["output"])
      not Map.has_key?(response, "output") and output != [] -> response_items(response, Enum.reverse(output))
      true -> {:error, 502, :invalid_response}
    end
  end

  # An empty envelope has no state to replay. Opaque or visible reasoning does:
  # Condukt 1.13's chat translation cannot preserve Responses reasoning items.
  defp unsupported_reasoning?(%{"type" => "reasoning"} = item) do
    Enum.any?(["encrypted_content", "summary", "content"], &(item[&1] not in [nil, "", []]))
  end

  defp unsupported_reasoning?(_item), do: false

  # HTTP 200 does not mean an SSE request succeeded. Use only known structured
  # codes, never message text (which can contain prompts or misleading words).
  defp upstream_error(%{"code" => code}) when code in ["rate_limit_exceeded", "slow_down"],
    do: {:error, 429, :rate_limited}

  defp upstream_error(%{"code" => code})
       when code in [
              "insufficient_quota",
              "credit_balance_exhausted",
              "organization_spend_limit_exceeded",
              "project_spend_limit_exceeded"
            ], do: {:error, 402, :billing}

  defp upstream_error(%{"code" => code}) when code in ["context_length_exceeded", "invalid_prompt"],
    do: {:error, 400, :invalid_request}

  defp upstream_error(%{"type" => "invalid_request_error"}), do: {:error, 400, :invalid_request}
  defp upstream_error(%{"type" => "usage_limit_reached"}), do: {:error, 429, :rate_limited}

  defp upstream_error(_error), do: {:error, 502, :upstream_error}

  defp response_items(response, output) do
    text =
      for %{"type" => "message", "content" => parts} <- output,
          %{"type" => "output_text", "text" => text} <- parts,
          do: text

    calls =
      for %{"type" => "function_call"} = item <- output do
        tool_call(item["call_id"], item["name"], item["arguments"])
      end

    if Enum.any?(output, &unsupported_reasoning?/1),
      do: {:error, 502, :unsupported_reasoning},
      else: completion(response["id"], response["model"], text, calls, response["usage"] || %{})
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

  defp messages_completion(%{"stop_reason" => "max_tokens"}), do: {:error, 502, :incomplete_response}

  defp messages_completion(%{"id" => id, "model" => model, "content" => parts} = body) do
    text = for %{"type" => "text", "text" => text} <- parts, do: text

    calls =
      for %{"type" => "tool_use", "id" => id, "name" => name, "input" => input} <- parts do
        tool_call(id, name, JSON.encode!(input))
      end

    completion(id, model, text, calls, body["usage"] || %{})
  end

  defp messages_completion(_body), do: {:error, 502, :invalid_response}

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
