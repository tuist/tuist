defmodule Condukt.RetryTest do
  use ExUnit.Case, async: true

  alias Condukt.Retry
  alias ReqLLM.Providers.GoogleVertex
  alias ReqLLM.Providers.OpenAI.ResponsesAPI
  alias ReqLLM.Step.Error, as: StepError
  alias ReqLLM.Streaming.Failure

  describe "normalize/1" do
    test "nil and true return the default policy" do
      assert Retry.normalize(nil) == Retry.default()
      assert Retry.normalize(true) == Retry.default()
    end

    test "false returns the disabled policy" do
      assert Retry.normalize(false) == Retry.disabled()
      assert Retry.disabled().max_attempts == 1
    end

    test "a struct is returned as-is" do
      policy = %Retry{max_attempts: 7}
      assert Retry.normalize(policy) == policy
    end

    test "a keyword list overrides fields" do
      policy = Retry.normalize(max_attempts: 5, base_delay_ms: 10)
      assert policy.max_attempts == 5
      assert policy.base_delay_ms == 10
      assert policy.max_delay_ms == Retry.default().max_delay_ms
    end
  end

  describe "default_classify/1" do
    test "retries transient HTTP statuses on API.Request" do
      for status <- [408, 425, 429, 500, 502, 503, 504] do
        assert Retry.default_classify(%ReqLLM.Error.API.Request{status: status, reason: "x"}) == :retry
      end
    end

    test "stops on non-transient HTTP statuses" do
      for status <- [400, 401, 403, 404, 422] do
        assert Retry.default_classify(%ReqLLM.Error.API.Request{status: status, reason: "x"}) == :stop
      end
    end

    test "retries transient statuses wrapped in API.Stream" do
      cause = %ReqLLM.Error.API.Request{status: 503, reason: "overloaded"}
      assert Retry.default_classify(%ReqLLM.Error.API.Stream{reason: "Stream failed: ...", cause: cause}) == :retry
    end

    test "retries Stream errors with overload/rate-limit/timeout text when no cause is present" do
      for reason <- [
            "Stream failed: service overloaded, please try again later",
            "Stream failed: rate limit exceeded",
            "Stream failed: connection timed out"
          ] do
        assert Retry.default_classify(%ReqLLM.Error.API.Stream{reason: reason, cause: nil}) == :retry
      end
    end

    test "stops on Stream errors with non-transient text" do
      assert Retry.default_classify(%ReqLLM.Error.API.Stream{reason: "Stream failed: malformed response", cause: nil}) ==
               :stop
    end

    test "stops on unknown error shapes" do
      assert Retry.default_classify(:something_else) == :stop
      assert Retry.default_classify(%RuntimeError{message: "boom"}) == :stop
    end
  end

  describe "context_overflow?/1" do
    # Each error goes through ReqLLM's own pipeline from the provider's HTTP
    # status and body, so the shapes match what native sessions receive.
    test "detects context-length rejections from buffered requests" do
      errors = [
        anthropic:
          buffered_error(
            ReqLLM.Providers.Anthropic,
            400,
            ~s|{"type":"error","error":{"type":"invalid_request_error",| <>
              ~s|"message":"prompt is too long: 213462 tokens > 200000 maximum"}}|
          ),
        anthropic_with_max_tokens:
          buffered_error(
            ReqLLM.Providers.Anthropic,
            400,
            ~s|{"type":"error","error":{"type":"invalid_request_error",| <>
              ~s|"message":"input length and `max_tokens` exceed context limit: 188240 + 21333 > 200000, | <>
              ~s|decrease input length or `max_tokens` and try again"}}|
          ),
        anthropic_request_bytes:
          buffered_error(
            ReqLLM.Providers.Anthropic,
            413,
            ~s|{"type":"error","error":{"type":"request_too_large",| <>
              ~s|"message":"Request exceeds the maximum allowed number of bytes."}}|
          ),
        openai_responses:
          buffered_error(ReqLLM.Providers.OpenAI.ResponsesAPI, 400, %{
            "error" => %{
              "message" =>
                "Your input exceeds the context window of this model. Please adjust your input and try again.",
              "type" => "invalid_request_error",
              "param" => "input",
              "code" => "context_length_exceeded"
            }
          }),
        openai_chat:
          buffered_error(ReqLLM.Providers.OpenAI, 400, %{
            "error" => %{
              "message" =>
                "This model's maximum context length is 128000 tokens. However, your messages resulted in " <>
                  "130532 tokens. Please reduce the length of the messages.",
              "type" => "invalid_request_error",
              "param" => "messages",
              "code" => "context_length_exceeded"
            }
          }),
        google:
          buffered_error(
            ReqLLM.Providers.Google,
            400,
            ~s|{"error":{"code":400,"message":"The input token count | <>
              ~s|(1196265) exceeds the maximum number of tokens allowed (1048575).","status":"INVALID_ARGUMENT"}}|
          ),
        google_model_limit:
          buffered_error(
            ReqLLM.Providers.Google,
            400,
            ~s|{"error":{"code":400,"message":"Unable to submit request because the input token count is | <>
              ~s|106244 but model only supports up to 65536. Reduce the input token count and try again.",| <>
              ~s|"status":"INVALID_ARGUMENT"}}|
          ),
        vertex_gemini:
          vertex_gemini_error(
            "The input token count (1196265) exceeds the maximum number of tokens allowed (1048575).",
            "Summarise the repository."
          ),
        bedrock: buffered_error(nil, 400, %{"message" => "Input is too long for requested model."}),
        xai:
          buffered_error(nil, 400, %{
            "code" => "Client specified an invalid argument",
            "error" => "This model's maximum prompt length is 131072 but the request contains 537812 tokens."
          }),
        groq:
          buffered_error(nil, 400, %{
            "error" => %{
              "message" => "Please reduce the length of the messages or completion.",
              "type" => "invalid_request_error",
              "param" => "messages"
            }
          }),
        mistral:
          buffered_error(nil, 400, %{
            "object" => "error",
            "message" =>
              "Prompt contains 140000 tokens and 0 draft tokens, too large for model with 131072 maximum context length",
            "type" => "invalid_request_message_error"
          }),
        openai_compatible:
          buffered_error(nil, 400, %{
            "error" => %{"message" => "Input length (265330) exceeds model's maximum context length (262144)."}
          })
      ]

      for {provider, error} <- errors do
        assert Retry.context_overflow?(error), "expected #{provider} to be a context overflow: #{inspect(error)}"
        assert Retry.default_classify(error) == :stop
      end
    end

    test "detects context-length rejections that fail a stream" do
      errors = [
        anthropic:
          stream_error(
            400,
            ~s|{"type":"error","error":{"type":"invalid_request_error",| <>
              ~s|"message":"prompt is too long: 213462 tokens > 200000 maximum"}}|
          ),
        anthropic_request_bytes:
          stream_error(
            413,
            ~s|{"type":"error","error":{"type":"request_too_large",| <>
              ~s|"message":"Request exceeds the maximum allowed number of bytes."}}|
          ),
        openai:
          stream_error(
            400,
            ~s|{"error":{"message":"Your input exceeds the context window of this model. | <>
              ~s|Please adjust your input and try again.","type":"invalid_request_error","param":"input",| <>
              ~s|"code":"context_length_exceeded"}}|
          ),
        google:
          stream_error(
            400,
            ~s|[{"error":{"code":400,"message":"The input token count (1196265) exceeds the | <>
              ~s|maximum number of tokens allowed (1048575).","status":"INVALID_ARGUMENT"}}]|
          ),
        google_model_limit:
          stream_error(
            400,
            ~s|[{"error":{"code":400,"message":"Unable to submit request because the input token count is | <>
              ~s|106244 but model only supports up to 65536.","status":"INVALID_ARGUMENT"}}]|
          ),
        openai_response_failed:
          responses_stream_failure("Your input exceeds the context window of this model. Please adjust your input.")
      ]

      for {provider, error} <- errors do
        assert Retry.context_overflow?(error), "expected #{provider} to be a context overflow: #{inspect(error)}"
      end
    end

    test "does not treat other rejections as context overflow" do
      errors = [
        anthropic_output_limit:
          buffered_error(
            ReqLLM.Providers.Anthropic,
            400,
            ~s|{"type":"error","error":{"type":"invalid_request_error",| <>
              ~s|"message":"max_tokens: 100000 > 64000, which is the maximum allowed number of output tokens | <>
              ~s|for claude-sonnet-4-20250514"}}|
          ),
        anthropic_invalid_history:
          buffered_error(
            ReqLLM.Providers.Anthropic,
            400,
            ~s|{"type":"error","error":{"type":"invalid_request_error",| <>
              ~s|"message":"messages.2: `tool_use` ids were found without `tool_result` blocks immediately after"}}|
          ),
        anthropic_overloaded:
          stream_error(529, ~s|{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}|),
        openai_output_limit:
          buffered_error(ReqLLM.Providers.OpenAI, 400, %{
            "error" => %{
              "message" =>
                "max_tokens is too large: 50000. This model supports at most 16384 completion tokens, " <>
                  "whereas you provided 50000.",
              "type" => "invalid_request_error",
              "param" => "max_tokens",
              "code" => "invalid_value"
            }
          }),
        openai_tokens_per_minute:
          buffered_error(ReqLLM.Providers.OpenAI, 429, %{
            "error" => %{
              "message" =>
                "Request too large for gpt-4o in organization org-abc on tokens per min (TPM): Limit 30000, " <>
                  "Requested 45000. The input or output tokens must be reduced in order to run successfully.",
              "type" => "tokens",
              "code" => "rate_limit_exceeded"
            }
          }),
        google_invalid_argument:
          buffered_error(
            ReqLLM.Providers.Google,
            400,
            ~s|{"error":{"code":400,| <>
              ~s|"message":"Request contains an invalid argument.","status":"INVALID_ARGUMENT"}}|
          ),
        # The prompt is the user's text: quoting an overflow message in it must not count.
        overflow_text_in_request:
          buffered_error(
            ReqLLM.Providers.Google,
            400,
            ~s|{"error":{"code":400,"message":"Request contains an invalid argument.","status":"INVALID_ARGUMENT"}}|,
            ~s|{"contents":[{"parts":[{"text":"Why does Claude say prompt is too long?"}]}]}|
          ),
        # Vertex AI keeps the sent conversation next to the error; the history is not the error.
        vertex_gemini_history:
          vertex_gemini_error("Request contains an invalid argument.", "Why does Claude say prompt is too long?"),
        # Validation errors echo the request back in `detail[].input`.
        echoed_input:
          buffered_error(nil, 400, %{
            "detail" => [
              %{
                "type" => "missing",
                "loc" => ["body", "model"],
                "msg" => "Field required",
                "input" => %{"messages" => [%{"role" => "user", "content" => "Why does it say prompt is too long?"}]}
              }
            ]
          }),
        openai_response_failed: responses_stream_failure("The server had an error while processing your request."),
        transport: %ReqLLM.Error.API.Stream{
          reason: "Stream failed: %Mint.TransportError{reason: :closed}",
          cause: %Mint.TransportError{reason: :closed}
        },
        unknown: %RuntimeError{message: "prompt is too long"}
      ]

      for {name, error} <- errors do
        refute Retry.context_overflow?(error), "expected #{name} not to be a context overflow: #{inspect(error)}"
      end
    end
  end

  describe "with_retry/3" do
    test "returns the successful result without retrying" do
      attempts = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(Retry.normalize(max_attempts: 3, base_delay_ms: 1), fn -> false end, fn ->
          :counters.add(attempts, 1, 1)
          {:ok, :done}
        end)

      assert result == {:ok, :done}
      assert :counters.get(attempts, 1) == 1
    end

    test "retries transient errors up to max_attempts" do
      attempts = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(Retry.normalize(max_attempts: 3, base_delay_ms: 1, max_delay_ms: 2), fn -> false end, fn ->
          :counters.add(attempts, 1, 1)
          {:error, %ReqLLM.Error.API.Request{status: 503, reason: "overloaded"}}
        end)

      assert {:error, %ReqLLM.Error.API.Request{status: 503}} = result
      assert :counters.get(attempts, 1) == 3
    end

    test "succeeds after a transient failure" do
      attempts = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(Retry.normalize(max_attempts: 3, base_delay_ms: 1, max_delay_ms: 2), fn -> false end, fn ->
          case :counters.add(attempts, 1, 1) do
            _ ->
              if :counters.get(attempts, 1) < 2 do
                {:error, %ReqLLM.Error.API.Request{status: 503, reason: "overloaded"}}
              else
                {:ok, :recovered}
              end
          end
        end)

      assert result == {:ok, :recovered}
      assert :counters.get(attempts, 1) == 2
    end

    test "does not retry non-transient errors" do
      attempts = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(Retry.normalize(max_attempts: 3, base_delay_ms: 1, max_delay_ms: 2), fn -> false end, fn ->
          :counters.add(attempts, 1, 1)
          {:error, %ReqLLM.Error.API.Request{status: 400, reason: "bad request"}}
        end)

      assert {:error, %ReqLLM.Error.API.Request{status: 400}} = result
      assert :counters.get(attempts, 1) == 1
    end

    test "stops retrying once emitted? returns true" do
      attempts = :counters.new(1, [:atomics])
      emitted = :counters.new(1, [:atomics])

      emitted? = fn -> :counters.get(emitted, 1) > 0 end

      result =
        Retry.with_retry(Retry.normalize(max_attempts: 5, base_delay_ms: 1, max_delay_ms: 2), emitted?, fn ->
          :counters.add(attempts, 1, 1)
          :counters.add(emitted, 1, 1)
          {:error, %ReqLLM.Error.API.Request{status: 503, reason: "overloaded"}}
        end)

      assert {:error, %ReqLLM.Error.API.Request{status: 503}} = result
      assert :counters.get(attempts, 1) == 1
    end

    test "disabled policy runs exactly once" do
      attempts = :counters.new(1, [:atomics])

      result =
        Retry.with_retry(Retry.disabled(), fn -> false end, fn ->
          :counters.add(attempts, 1, 1)
          {:error, %ReqLLM.Error.API.Request{status: 503, reason: "overloaded"}}
        end)

      assert {:error, %ReqLLM.Error.API.Request{status: 503}} = result
      assert :counters.get(attempts, 1) == 1
    end

    test "an interrupted backoff returns its error without another attempt" do
      attempts = :counters.new(1, [:atomics])
      test_pid = self()

      task =
        Task.async(fn ->
          Retry.with_retry(
            Retry.default(),
            fn -> false end,
            fn ->
              :counters.add(attempts, 1, 1)
              {:error, %ReqLLM.Error.API.Request{status: 503, reason: "overloaded"}}
            end,
            fn _delay ->
              send(test_pid, {:waiting, self()})
              receive do: (:cancel -> {:error, :aborted})
            end
          )
        end)

      assert_receive {:waiting, worker}
      send(worker, :cancel)
      assert Task.await(task) == {:error, :aborted}
      assert :counters.get(attempts, 1) == 1
    end

    test "custom classify overrides default behavior" do
      attempts = :counters.new(1, [:atomics])

      policy =
        Retry.normalize(
          max_attempts: 3,
          base_delay_ms: 1,
          max_delay_ms: 2,
          classify: fn
            :please_retry -> :retry
            _ -> :stop
          end
        )

      result =
        Retry.with_retry(policy, fn -> false end, fn ->
          :counters.add(attempts, 1, 1)
          {:error, :please_retry}
        end)

      assert result == {:error, :please_retry}
      assert :counters.get(attempts, 1) == 3
    end
  end

  # A buffered request's error: the provider decodes the HTTP response, then
  # ReqLLM's error step wraps it together with the request that was sent.
  defp buffered_error(provider, status, body, request_body \\ "{}") do
    request = Req.new(url: "https://provider.test", body: request_body)
    response = Req.Response.new(status: status, body: body)
    {request, decoded} = if provider, do: provider.decode_response({request, response}), else: {request, response}
    {_request, error} = StepError.handle({request, decoded})
    error
  end

  # Vertex AI decodes a Gemini error body like a response, keeping the sent
  # conversation in its context, before ReqLLM's error step wraps it.
  defp vertex_gemini_error(message, prompt) do
    {:ok, model} = ReqLLM.model("google_vertex:gemini-2.5-pro")
    context = ReqLLM.Context.new([ReqLLM.Context.user(prompt)])
    request = Req.new(url: "https://vertex.test") |> Req.Request.put_private(:model, model)
    request = %{request | options: Map.put(request.options, :context, context)}
    body = %{"error" => %{"code" => 400, "message" => message, "status" => "INVALID_ARGUMENT"}}
    {request, decoded} = GoogleVertex.decode_response({request, Req.Response.new(status: 400, body: body)})
    {_request, error} = StepError.handle({request, decoded})
    error
  end

  # The error an OpenAI Responses stream returns after a `response.failed` event.
  defp responses_stream_failure(message) do
    {:ok, model} = ReqLLM.model("openai:gpt-4o")
    error = %{"code" => "context_length_exceeded", "message" => message}
    data = %{"type" => "response.failed", "response" => %{"id" => "resp_1", "status" => "failed", "error" => error}}
    chunks = ResponsesAPI.decode_stream_event(%{event: "response.failed", data: data}, model)
    Enum.find_value(chunks, & &1.metadata[:error])
  end

  # The error a stream raises when the provider answers with an HTTP error.
  defp stream_error(status, body) do
    cause = Failure.api_error(status, body, [])
    %ReqLLM.Error.API.Stream{reason: "Stream failed: #{inspect(cause)}", cause: cause}
  end
end
