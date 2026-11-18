defmodule Condukt.Plug do
  @moduledoc """
  Exposes Condukt agents and typed operations as HTTP routes.

  `Condukt.Plug` is a regular Plug that runs either a statically declared
  `Condukt.Operation` or a module-defined one-shot agent.

      post "/review-pr",
        to: Condukt.Plug,
        init_opts: [
          agent: MyApp.ReviewAgent,
          operation: :review_pr,
          run_opts: [timeout: 120_000]
        ]

  Agent routes omit `:operation`. The request body can be a raw prompt string,
  a JSON string, or a JSON object with an optional `"prompt"` string. If no
  prompt is provided, `:prompt` is used, falling back to an empty prompt.

      post "/assistant",
        to: Condukt.Plug,
        init_opts: [
          agent: MyApp.AssistantAgent,
          prompt: "Help with this request.",
          run_opts: [timeout: 120_000]
        ]

  Operation route request bodies must be JSON objects. Agent route request
  bodies can be raw text prompts, JSON strings, or JSON objects. If
  `Plug.Parsers` has already parsed the body, `conn.body_params` is reused.
  Otherwise this plug reads and decodes the body itself.

  Successful responses are encoded as:

      {"ok": true, "result": {...}}

  Error responses are encoded as:

      {"ok": false, "error": {"code": "invalid_input", "message": "..."}}
  """

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, opts) do
    case required_opt(opts, :agent) do
      {:ok, agent_module} ->
        dispatch(conn, opts, agent_module)

      {:error, reason} ->
        {status, code, message} = error_response(reason)
        json(conn, status, %{ok: false, error: %{code: code, message: message}})
    end
  end

  defp dispatch(conn, opts, agent_module) do
    case Keyword.fetch(opts, :operation) do
      {:ok, operation_name} -> run_operation(conn, opts, agent_module, operation_name)
      :error -> run_agent(conn, opts, agent_module)
    end
  end

  defp run_operation(conn, opts, agent_module, operation_name) do
    with {:ok, input} <- input(conn, opts),
         {:ok, result} <- Condukt.Operation.run(agent_module, operation_name, input, run_opts(opts, conn)) do
      json(conn, 200, %{ok: true, result: result})
    else
      {:error, reason} ->
        {status, code, message} = error_response(reason)
        json(conn, status, %{ok: false, error: %{code: code, message: message}})
    end
  end

  defp run_agent(conn, opts, agent_module) do
    with {:ok, body} <- agent_body(conn),
         {:ok, prompt} <- prompt(conn, opts, body),
         {:ok, result} <- Condukt.run(agent_module, prompt, run_opts(opts, conn)) do
      json(conn, 200, %{ok: true, result: result})
    else
      {:error, reason} ->
        {status, code, message} = error_response(reason)
        json(conn, status, %{ok: false, error: %{code: code, message: message}})
    end
  end

  defp required_opt(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_option, key}}
    end
  end

  defp input(conn, opts) do
    case Keyword.get(opts, :input) do
      input_fun when is_function(input_fun, 1) -> normalize_input(input_fun.(conn))
      nil -> body_input(conn)
    end
  end

  defp normalize_input(input) when is_map(input), do: {:ok, input}
  defp normalize_input(_input), do: {:error, :input_must_be_a_map}

  defp prompt(_conn, _opts, {:prompt, prompt}), do: validate_prompt(prompt)

  defp prompt(conn, opts, {:params, params}) do
    prompt_key = Keyword.get(opts, :prompt_param, "prompt")

    case fetch_param(params, prompt_key) do
      {:ok, prompt} -> validate_prompt(prompt)
      :error -> prompt_from_unparsed_body(conn, opts)
    end
  end

  defp fetch_param(params, key) when is_atom(key) do
    case Map.fetch(params, Atom.to_string(key)) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(params, key)
    end
  end

  defp fetch_param(params, key) when is_binary(key) do
    Map.fetch(params, key)
  end

  defp route_prompt(conn, opts) do
    case Keyword.get(opts, :prompt, "") do
      prompt_fun when is_function(prompt_fun, 1) -> validate_prompt(prompt_fun.(conn))
      prompt -> validate_prompt(prompt)
    end
  end

  defp prompt_from_unparsed_body(conn, opts) do
    case read_agent_body(conn) do
      {:ok, {:prompt, prompt}} -> validate_prompt(prompt)
      {:ok, {:params, _params}} -> route_prompt(conn, opts)
      {:error, {:body_read_failed, :stream_consumed}} -> route_prompt(conn, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_prompt(prompt) when is_binary(prompt), do: {:ok, prompt}
  defp validate_prompt(_prompt), do: {:error, :prompt_must_be_a_string}

  defp agent_body(conn) do
    case body_params(conn) do
      {:ok, params} when is_map(params) -> {:ok, {:params, params}}
      {:ok, prompt} when is_binary(prompt) -> {:ok, {:prompt, prompt}}
      {:ok, _params} -> {:error, :agent_body_must_be_a_prompt_or_object}
      :unfetched -> read_agent_body(conn)
    end
  end

  defp body_input(conn) do
    case body_params(conn) do
      {:ok, params} -> normalize_input(params)
      :unfetched -> read_json_body(conn)
    end
  end

  defp body_params(conn) do
    case Map.fetch(conn, :body_params) do
      {:ok, %{__struct__: Plug.Conn.Unfetched}} -> :unfetched
      {:ok, params} -> {:ok, params}
      :error -> :unfetched
    end
  end

  defp read_json_body(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, "", _conn} -> {:ok, %{}}
      {:ok, body, _conn} -> decode_json(body)
      {:more, _partial, _conn} -> {:error, :body_too_large}
      {:error, reason} -> {:error, {:body_read_failed, reason}}
    end
  end

  defp read_agent_body(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, "", _conn} -> {:ok, {:params, %{}}}
      {:ok, body, _conn} -> decode_agent_body(conn, body)
      {:more, _partial, _conn} -> {:error, :body_too_large}
      {:error, reason} -> {:error, {:body_read_failed, reason}}
    end
  end

  defp decode_agent_body(conn, body) do
    case JSON.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, {:params, decoded}}
      {:ok, prompt} when is_binary(prompt) -> {:ok, {:prompt, prompt}}
      {:ok, _decoded} -> {:error, :agent_body_must_be_a_prompt_or_object}
      {:error, reason} -> decode_agent_body_fallback(conn, body, reason)
    end
  end

  defp decode_agent_body_fallback(conn, body, reason) do
    if json_request?(conn) do
      {:error, {:invalid_json, reason}}
    else
      {:ok, {:prompt, body}}
    end
  end

  defp decode_json(body) do
    case JSON.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, _decoded} -> {:error, :json_body_must_be_an_object}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp json_request?(conn) do
    case Plug.Conn.get_req_header(conn, "content-type") do
      [content_type | _] -> content_type |> String.downcase() |> String.contains?("json")
      [] -> false
    end
  end

  defp run_opts(opts, conn) do
    case Keyword.get(opts, :run_opts, []) do
      fun when is_function(fun, 1) -> fun.(conn)
      run_opts when is_list(run_opts) -> run_opts
    end
  end

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, JSON.encode!(body))
    |> Plug.Conn.halt()
  end

  defp error_response({:missing_option, key}) do
    {500, "missing_option", "Missing required Condukt.Plug option #{inspect(key)}."}
  end

  defp error_response({:unknown_operation, operation_name}) do
    {404, "unknown_operation", "Unknown operation #{inspect(operation_name)}."}
  end

  defp error_response({:invalid_input, reason}) do
    {422, "invalid_input", validation_message(reason)}
  end

  defp error_response({:invalid_output, reason}) do
    {502, "invalid_output", validation_message(reason)}
  end

  defp error_response({:invalid_json, reason}) do
    {400, "invalid_json", "Request body is not valid JSON: #{inspect(reason)}."}
  end

  defp error_response(:json_body_must_be_an_object) do
    {400, "invalid_json", "Request body must be a JSON object."}
  end

  defp error_response(:input_must_be_a_map) do
    {400, "invalid_input", "Route input must be a map."}
  end

  defp error_response(:prompt_must_be_a_string) do
    {400, "invalid_prompt", "Route prompt must be a string."}
  end

  defp error_response(:agent_body_must_be_a_prompt_or_object) do
    {400, "invalid_input", "Agent route body must be a prompt string or a JSON object."}
  end

  defp error_response(:body_too_large) do
    {413, "body_too_large", "Request body is too large."}
  end

  defp error_response({:body_read_failed, reason}) do
    {400, "body_read_failed", "Could not read request body: #{inspect(reason)}."}
  end

  defp error_response(:no_result_submitted) do
    {502, "no_result_submitted", "The agent finished without submitting a structured result."}
  end

  defp error_response(reason) do
    {500, "operation_failed", inspect(reason)}
  end

  defp validation_message(%JSV.ValidationError{} = error), do: Exception.message(error)
  defp validation_message(reason), do: inspect(reason)
end
