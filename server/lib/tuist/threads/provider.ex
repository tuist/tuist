defmodule Tuist.Threads.Provider do
  @moduledoc """
  Buffered, server-owned subscription transport, adapted from Atlas's personal
  providers. Session options contain only a user ID and sentinel credentials.
  Each HTTP turn reloads that person's credentials for the immutable thread
  provider/model. There is no provider, workspace, relay, or API-key fallback.
  """

  @behaviour Plug

  import Plug.Conn

  alias Tuist.Accounts.AISubscriptions
  alias Tuist.Accounts.User
  alias Tuist.Repo
  alias Tuist.Threads.ModelFence

  def default_model(:chatgpt), do: "gpt-6-sol"
  @doc "Metadata-only readiness check; never puts personal credentials in Condukt options."
  def client_opts(%User{id: user_id} = user, %{provider: "chatgpt", model: model}) do
    if valid_model_id?(model) and Enum.any?(AISubscriptions.list(user), &(&1.provider == :chatgpt and &1.connected)) do
      {:ok,
       [
         # The internal contract stays Chat Completions regardless of the
         # personal subscription's upstream protocol or model catalog routing.
         model:
           ReqLLM.model!(%{
             id: model,
             provider: :openai,
             extra: %{wire: %{protocol: "openai_chat"}}
           }),
         api_key: "server-owned",
         base_url: "http://thread-provider.invalid",
         retry: false,
         llm_request_options: [req_http_options: [plug: {__MODULE__, user_id: user_id, model: model}]]
       ]}
    else
      {:error, :not_connected}
    end
  end

  def client_opts(_user, _thread), do: {:error, :not_connected}

  @doc "Fresh account-scoped provider catalog; credentials and upstream instructions never leave this boundary."
  def models(user) do
    Enum.reduce(AISubscriptions.list(user), %{models: [], errors: []}, fn
      %{provider: :chatgpt, connected: true}, catalog ->
        result = with {:ok, %{access_token: token}} <- AISubscriptions.credentials(user, :chatgpt), do: catalog(token)

        case result do
          {:ok, models} -> %{catalog | models: catalog.models ++ models}
          _ -> %{catalog | errors: catalog.errors ++ [%{provider: "chatgpt", code: "models_unavailable"}]}
        end

      %{provider: :claude, connected: true}, catalog ->
        # Claude subscription credentials are not approved for third-party
        # inference. Do not impersonate Claude Code to bypass this restriction.
        %{catalog | errors: catalog.errors ++ [%{provider: "claude", code: "unsupported_subscription"}]}

      _, catalog ->
        catalog
    end)
  end

  def validate_model(user, provider, model) do
    if provider == "chatgpt" and valid_model_id?(model) and
         Enum.any?(models(user).models, &(&1.provider == provider and &1.id == model)),
       do: :ok,
       else: {:error, :model_unavailable}
  end

  def catalog(token, http_opts \\ []) do
    with {:ok, account_id} <- chatgpt_account_id(token),
         {:ok, %{status: 200, body: %{"models" => models}}} when is_list(models) <-
           Req.get(
             Keyword.merge(http_opts,
               url: "https://chatgpt.com/backend-api/codex/models",
               params: [client_version: "0.159.2"],
               headers: [{"authorization", "Bearer " <> token}, {"chatgpt-account-id", account_id}],
               retry: false,
               redirect: false,
               receive_timeout: 15_000,
               connect_options: [timeout: 5_000]
             )
           ) do
      choices =
        models
        |> Enum.filter(fn model ->
          is_map(model) and model["visibility"] == "list" and valid_model_id?(model["slug"]) and
            is_binary(model["display_name"]) and String.length(model["display_name"]) in 1..100 and
            is_list(model["supported_reasoning_levels"]) and
            Enum.any?(model["supported_reasoning_levels"], &match?(%{"effort" => "low"}, &1))
        end)
        |> Enum.uniq_by(& &1["slug"])
        |> Enum.take(31)
        |> Enum.map(&%{provider: "chatgpt", id: &1["slug"], name: &1["display_name"]})

      {:ok, choices}
    else
      _ -> {:error, :models_unavailable}
    end
  end

  defp valid_model_id?(id) when is_binary(id), do: Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}\z/, id)
  defp valid_model_id?(_), do: false

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    with true <- ModelFence.authorized?(conn),
         %User{} = user <- Repo.get(User, Keyword.fetch!(opts, :user_id)),
         {:ok, body, conn} <- read_body(conn),
         {:ok, params} when is_map(params) <- JSON.decode(body) do
      case personal_completion(conn, user, Map.put(params, "model", Keyword.fetch!(opts, :model))) do
        {:ok, completion} -> respond(conn, 200, completion)
        {:error, status, category} -> unavailable(conn, status, category)
      end
    else
      false -> unavailable(conn, 409, :fenced)
      _ -> unavailable(conn, 503, :provider_unavailable)
    end
  end

  defp personal_completion(conn, user, params) do
    case AISubscriptions.credentials(user, :chatgpt) do
      {:ok, %{access_token: token}} ->
        # Refreshing credentials can take time. Recheck immediately before every
        # dispatch, not just at the outer plug or before refreshing.
        if ModelFence.authorized?(conn),
          do: complete(:chatgpt, token, params),
          else: {:error, 409, :fenced}

      {:error, :not_connected} ->
        {:error, 503, :not_connected}

      {:error, _category} ->
        {:error, 502, :provider_auth}
    end
  end

  defp unavailable(conn, status, category) do
    respond(conn, status, %{
      error: %{
        message: "The assistant's inference provider is unavailable.",
        type: "provider_error",
        code: Atom.to_string(category)
      }
    })
  end

  defp respond(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, JSON.encode!(body))
  end

  @doc "Subscription protocol adapter. HTTP options allow Req plugs; never persist token or returned errors."
  def complete(provider, token, params, http_opts \\ [])

  def complete(:chatgpt, token, params, http_opts) do
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
             responses_request(params),
             http_opts
           ) do
      responses_completion(body)
    end
  end

  def complete(:claude, _token, _params, _http_opts), do: {:error, 403, :unsupported_subscription}

  defp request(url, headers, body, http_opts) do
    opts =
      Keyword.merge(http_opts,
        url: url,
        headers: headers,
        json: body,
        retry: false,
        redirect: false,
        receive_timeout: 45_000,
        connect_options: [timeout: 5_000]
      )

    case Req.post(opts) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, status, http_error_category(status, body)}
      {:error, %{reason: :timeout}} -> {:error, 504, :timeout}
      {:error, _reason} -> {:error, 502, :request_failed}
    end
  end

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
      "model" => params["model"] || default_model(:chatgpt),
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
        content when content in [nil, ""] -> []
        content -> [%{"role" => message["role"], "content" => responses_content(content, message["role"])}]
      end

    calls =
      Enum.map(message["tool_calls"] || [], fn call ->
        Map.merge(call["function"], %{"type" => "function_call", "call_id" => call["id"]})
      end)

    reasoning =
      for %{"format" => "tuist-codex-v1", "item" => %{"type" => "reasoning"} = item} <-
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

  # Buffer complete SSE frames, never deltas. Done items are usable only after
  # a successful terminal event. CRLF and multi-line data follow the SSE wire format.
  defp responses_completion(body) when is_binary(body) do
    body
    |> String.replace("\r\n", "\n")
    |> String.split("\n\n")
    |> Enum.reduce_while([], fn frame, output ->
      data =
        frame
        |> String.split("\n")
        |> Enum.filter(&String.starts_with?(&1, "data:"))
        |> Enum.map_join("\n", fn "data:" <> value -> String.replace_prefix(value, " ", "") end)

      case JSON.decode(data) do
        {:ok, event} -> responses_event(event, output)
        _ -> {:cont, output}
      end
    end)
    |> case do
      output when is_list(output) -> {:error, 502, :incomplete_stream}
      result -> result
    end
  end

  defp responses_completion(_body), do: {:error, 502, :invalid_response}

  defp responses_event(%{"type" => "response.output_item.done", "item" => item}, output) when is_map(item),
    do: {:cont, [item | output]}

  defp responses_event(%{"type" => type, "response" => response}, output)
       when type in ["response.completed", "response.done"] and is_map(response) do
    result =
      cond do
        response["status"] not in [nil, "completed"] -> {:error, 502, :invalid_response}
        is_list(response["output"]) -> response_items(response, response["output"])
        not Map.has_key?(response, "output") and output != [] -> response_items(response, Enum.reverse(output))
        true -> {:error, 502, :invalid_response}
      end

    {:halt, result}
  end

  defp responses_event(%{"type" => "response.failed", "response" => %{"error" => error}}, _output),
    do: {:halt, upstream_error(error)}

  defp responses_event(%{"type" => "error"} = event, _output), do: {:halt, upstream_error(event["error"] || event)}
  defp responses_event(%{"type" => "response.incomplete"}, _output), do: {:halt, {:error, 502, :incomplete_response}}

  defp responses_event(%{"type" => type}, _output)
       when type in ["response.completed", "response.done", "response.failed"],
       do: {:halt, {:error, 502, :invalid_response}}

  defp responses_event(_event, output), do: {:cont, output}

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
      for %{"type" => "function_call"} = item <- output, do: tool_call(item["call_id"], item["name"], item["arguments"])

    reasoning = for %{"type" => "reasoning"} = item <- output, do: %{"format" => "tuist-codex-v1", "item" => item}
    {:ok, completion} = completion(response["id"], response["model"], text, calls, response["usage"] || %{})
    {:ok, put_in(completion, ["choices", Access.at(0), "message", "reasoning_details"], reasoning)}
  end

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

  defp tool_call(id, name, arguments),
    do: %{"id" => id, "type" => "function", "function" => %{"name" => name, "arguments" => arguments}}

  defp conversation(params), do: Enum.reject(params["messages"], &(&1["role"] in ["system", "developer"]))

  defp system_text(params) do
    params["messages"] |> Enum.filter(&(&1["role"] in ["system", "developer"])) |> Enum.map_join("\n", & &1["content"])
  end
end
