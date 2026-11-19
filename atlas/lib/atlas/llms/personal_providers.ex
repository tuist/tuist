defmodule Atlas.LLMs.PersonalProviders do
  @moduledoc """
  Subscription-account protocols, not OpenAI/Anthropic API-key endpoints.
  Translates the buffered OpenAI tool protocol used by Orbit to Codex Responses
  and Claude Messages. Provider errors return sanitized statuses and categories;
  diagnostics contain fixed categories, never upstream messages or bodies.
  """

  alias OpenTelemetry.Tracer

  require Logger

  @timeout :timer.seconds(45)

  def default_model("chatgpt"), do: "gpt-6-sol"
  def default_model("claude"), do: "claude-sonnet-4-6"

  @doc "Account-scoped Codex catalog, projected to model IDs and names only."
  def models(token) do
    result =
      with {:ok, account_id} <- chatgpt_account_id(token),
           {:ok, %{status: 200, body: %{"models" => models}}} when is_list(models) <-
             Req.get(
               url: "https://chatgpt.com/backend-api/codex/models",
               # Catalog protocol version supported by this adapter, not a client identity.
               params: [client_version: "0.159.2"],
               headers: [{"authorization", "Bearer " <> token}, {"chatgpt-account-id", account_id}],
               retry: false,
               redirect: false,
               receive_timeout: 15_000,
               finch: [conn_opts: [transport_opts: [timeout: 5_000]]]
             ) do
        models =
          models
          |> Enum.filter(fn model ->
            is_map(model) and model["visibility"] == "list" and valid_model_id?(model["slug"]) and
              is_binary(model["display_name"]) and String.length(model["display_name"]) in 1..100 and
              is_list(model["supported_reasoning_levels"]) and
              Enum.any?(model["supported_reasoning_levels"], &match?(%{"effort" => "low"}, &1))
          end)
          |> Enum.uniq_by(& &1["slug"])
          |> Enum.take(31)
          |> Enum.map(&%{id: "chatgpt:" <> &1["slug"], name: &1["display_name"], provider: "ChatGPT"})

        {:ok, models}
      else
        {:ok, %{status: status, body: body}} -> {:error, status, http_error_category(status, body)}
        {:error, status, category} -> {:error, status, category}
        _ -> {:error, 502, :invalid_response}
      end

    report_result("chatgpt", result)
  end

  def valid_model_id?(id) when is_binary(id), do: Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}\z/, id)
  def valid_model_id?(_id), do: false

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

    Logger.error("Orbit personal provider failed: provider=#{provider} category=#{category} status=#{status}")
    {:error, status, category}
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
      {:ok, %{status: status, body: body}} -> {:error, status, http_error_category(status, body)}
      {:error, %{reason: :timeout}} -> {:error, 504, :timeout}
      {:error, _reason} -> {:error, 502, :request_failed}
    end
  end

  # A proxy may return JSON with a non-JSON content type. Decode only for the
  # same fixed diagnostics; never log its body or infer categories from text.
  defp http_error_category(status, body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, %{} = decoded} -> http_error_category(status, decoded)
      _ -> :http_error
    end
  end

  defp http_error_category(_status, %{"error" => %{"code" => "model_not_found"}}), do: :model_not_found
  defp http_error_category(_status, %{"error" => %{"code" => "context_length_exceeded"}}), do: :context_length
  defp http_error_category(400, %{"error" => %{"param" => "reasoning.effort"}}), do: :unsupported_reasoning_effort

  defp http_error_category(400, %{"error" => %{"param" => "tools"}}), do: :invalid_tools
  defp http_error_category(400, %{"error" => %{"param" => "tools[" <> _}}), do: :invalid_tools
  defp http_error_category(_status, _body), do: :http_error

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
      "model" => params["model"] || default_model("chatgpt"),
      "reasoning" => %{"effort" => "low"},
      "include" => ["reasoning.encrypted_content"],
      "store" => false,
      "stream" => true,
      "instructions" => system_text(params),
      "input" => Enum.flat_map(conversation(params), &responses_message/1),
      "tools" =>
        Enum.map(
          params["tools"] || [],
          &(&1["function"] |> Map.put("type", "function") |> Map.put_new("strict", false))
        ),
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

    reasoning =
      for %{"format" => "atlas-codex-v1", "item" => %{"type" => "reasoning"} = item} <-
            message["reasoning_details"] || [],
          message["role"] == "assistant",
          do: item

    reasoning ++ text ++ calls
  end

  defp responses_content(content, role) when is_binary(content),
    do: responses_content([%{"type" => "text", "text" => content}], role)

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
      is_list(response["output"]) -> response_items(response, response["output"])
      not Map.has_key?(response, "output") and output != [] -> response_items(response, Enum.reverse(output))
      true -> {:error, 502, :invalid_response}
    end
  end

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

  defp upstream_error(%{"code" => "model_not_found"}), do: {:error, 400, :model_not_found}
  defp upstream_error(%{"code" => "context_length_exceeded"}), do: {:error, 400, :context_length}

  defp upstream_error(%{"code" => "invalid_prompt"}), do: {:error, 400, :invalid_request}

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

    reasoning = for %{"type" => "reasoning"} = item <- output, do: %{"format" => "atlas-codex-v1", "item" => item}

    {:ok, completion} = completion(response["id"], response["model"], text, calls, response["usage"] || %{})
    {:ok, put_in(completion, ["choices", Access.at(0), "message", "reasoning_details"], reasoning)}
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
