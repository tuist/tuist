defmodule Condukt.OperationTest do
  use ExUnit.Case, async: true

  alias Condukt.Operation
  alias Condukt.Test.LLMProvider
  alias Condukt.TraceContext
  alias ReqLLM.Message
  alias ReqLLM.ToolCall

  defmodule ReviewAgent do
    use Condukt

    @impl true
    def tools, do: []

    @impl true
    def system_prompt, do: "You are a code reviewer."

    operation(:review_pr,
      input: %{
        type: "object",
        properties: %{
          repo: %{type: "string"},
          pr_number: %{type: "integer"}
        },
        required: ["repo", "pr_number"]
      },
      output: %{
        type: "object",
        properties: %{
          verdict: %{type: "string", enum: ["approve", "request_changes", "comment"]},
          summary: %{type: "string"}
        },
        required: ["verdict", "summary"]
      },
      instructions: "Review the PR and report a verdict."
    )
  end

  defmodule EmptyAgent do
    use Condukt
  end

  defmodule AgentModuleTool do
    use Condukt.Tool

    @impl true
    def name, do: "agent_module"

    @impl true
    def description, do: "Returns the session agent module."

    @impl true
    def parameters, do: %{type: "object", properties: %{}}

    @impl true
    def call(_args, context), do: {:ok, inspect(context.agent_module)}
  end

  defmodule ContextAgent do
    use Condukt

    @impl true
    def tools, do: [AgentModuleTool]

    operation(:inspect_context,
      input: %{
        type: "object",
        properties: %{subject: %{type: "string"}},
        required: ["subject"]
      },
      output: %{
        type: "object",
        properties: %{module_seen: %{type: "string"}},
        required: ["module_seen"]
      },
      instructions: "Inspect the operation context."
    )
  end

  describe "compile-time declaration" do
    test "generates a function on the agent module for each operation" do
      assert function_exported?(ReviewAgent, :review_pr, 1)
      assert function_exported?(ReviewAgent, :review_pr, 2)
    end

    test "exposes operation metadata via __operations__/0" do
      ops = ReviewAgent.__operations__()
      assert Map.has_key?(ops, :review_pr)
      op = ops[:review_pr]
      assert %Operation{name: :review_pr} = op
      assert op.instructions =~ "Review the PR"
      assert op.input_schema.required == ["repo", "pr_number"]
      assert op.output_schema.required == ["verdict", "summary"]
    end

    test "__operation__/1 returns :error for unknown names" do
      assert :error = ReviewAgent.__operation__(:does_not_exist)
    end

    test "agents without operations expose an empty operation set" do
      assert %{} = EmptyAgent.__operations__()
      assert :error = EmptyAgent.__operation__(:does_not_exist)
    end
  end

  describe "input validation" do
    test "rejects args missing required fields" do
      assert {:error, {:invalid_input, %JSV.ValidationError{}}} =
               ReviewAgent.review_pr(%{repo: "tuist/condukt"})
    end

    test "rejects args with wrong types" do
      assert {:error, {:invalid_input, %JSV.ValidationError{}}} =
               ReviewAgent.review_pr(%{repo: "tuist/condukt", pr_number: "not-an-integer"})
    end

    test "rejects non-map args" do
      assert {:error, {:invalid_input, _}} = ReviewAgent.review_pr("not a map")
    end

    test "unknown operation returns :unknown_operation error" do
      assert {:error, {:unknown_operation, :missing}} =
               Operation.run(ReviewAgent, :missing, %{})
    end

    test "operation-free agents return :unknown_operation errors" do
      assert {:error, {:unknown_operation, :missing}} =
               Operation.run(EmptyAgent, :missing, %{})
    end
  end

  describe "telemetry" do
    test "emits :start and :stop around an operation invocation" do
      handler_id = "operation-telemetry-#{inspect(make_ref())}"
      test_pid = self()

      :telemetry.attach_many(
        handler_id,
        [
          [:condukt, :operation, :start],
          [:condukt, :operation, :stop]
        ],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      # Use the input-validation failure path so we don't need ReqLLM mocks here.
      assert {:error, {:invalid_input, _}} = ReviewAgent.review_pr(%{repo: "x"})

      assert_receive {:telemetry, [:condukt, :operation, :start], %{system_time: _},
                      %{agent: ReviewAgent, operation: :review_pr}}

      assert_receive {:telemetry, [:condukt, :operation, :stop], %{duration: _},
                      %{agent: ReviewAgent, operation: :review_pr}}
    end
  end

  describe "end-to-end happy path" do
    test "passes trace context and request options through operations" do
      submit =
        ToolCall.new("call_1", "submit_result", JSON.encode!(%{"verdict" => "approve", "summary" => "Looks good."}))

      {model, model_id} =
        LLMProvider.model([
          LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [submit]}, :tool_calls),
          LLMProvider.text_response("Done.")
        ])

      assert {:ok, %{verdict: "approve", summary: "Looks good."}} =
               ReviewAgent.review_pr(%{repo: "tuist/condukt", pr_number: 1},
                 id: "operation-session",
                 model: model,
                 trace_context: trace_context(),
                 llm_request_options: [req_http_options: [headers: [{"x-tenant", "atlas"}]]]
               )

      assert_receive {LLMProvider, :request, ^model_id, _context, opts}
      headers = opts |> Keyword.fetch!(:req_http_options) |> Keyword.fetch!(:headers)

      assert {"x-tenant", "atlas"} in headers
      assert Enum.any?(headers, fn {name, _value} -> String.downcase(name) == "traceparent" end)
      assert {"baggage", "upstream=value,condukt.session.id=operation-session"} in headers
    end

    test "lets operations opt out of a calling process trace context" do
      submit =
        ToolCall.new("call_1", "submit_result", JSON.encode!(%{"verdict" => "approve", "summary" => "Looks good."}))

      {model, model_id} =
        LLMProvider.model([
          LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [submit]}, :tool_calls),
          LLMProvider.text_response("Done.")
        ])

      TraceContext.put_current(trace_context())
      on_exit(&TraceContext.clear_current/0)

      assert {:ok, %{verdict: "approve", summary: "Looks good."}} =
               ReviewAgent.review_pr(%{repo: "tuist/condukt", pr_number: 1},
                 model: model,
                 trace_context: false
               )

      assert_receive {LLMProvider, :request, ^model_id, _context, opts}
      refute opts[:req_http_options]
    end

    test "runs the agent loop, captures submit_result, validates, and returns atomized output" do
      submitted_args = %{"verdict" => "approve", "summary" => "Looks good."}

      tool_call = ToolCall.new("call_1", "submit_result", JSON.encode!(submitted_args))

      {model, model_id} =
        LLMProvider.model([
          LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls),
          LLMProvider.text_response("Done.")
        ])

      assert {:ok, %{verdict: "approve", summary: "Looks good."}} =
               ReviewAgent.review_pr(%{repo: "tuist/condukt", pr_number: 1}, model: model)

      assert_receive {LLMProvider, :request, ^model_id, _context, first_opts}
      assert Enum.find(first_opts[:tools], &(&1.name == "submit_result"))

      assert_receive {LLMProvider, :request, ^model_id, _context, _second_opts}
    end

    test "returns :no_result_submitted when the model never calls submit_result" do
      {model, model_id} = LLMProvider.model([LLMProvider.text_response("I refuse to submit.")])

      assert {:error, :no_result_submitted} =
               ReviewAgent.review_pr(%{repo: "tuist/condukt", pr_number: 1}, model: model)

      assert_receive {LLMProvider, :request, ^model_id, _context, _opts}
    end

    test "keeps the declaring agent module in tool context" do
      submitted_args = %{"module_seen" => inspect(ContextAgent)}

      inspect_call = ToolCall.new("call_1", "agent_module", JSON.encode!(%{}))
      submit_call = ToolCall.new("call_2", "submit_result", JSON.encode!(submitted_args))

      {model, model_id} =
        LLMProvider.model([
          LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [inspect_call]}, :tool_calls),
          LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [submit_call]}, :tool_calls),
          LLMProvider.text_response("Done.")
        ])

      assert {:ok, %{module_seen: module_seen}} =
               ContextAgent.inspect_context(%{subject: "context"}, model: model)

      assert module_seen == inspect(ContextAgent)

      assert_receive {LLMProvider, :request, ^model_id, _context, first_opts}
      assert Enum.find(first_opts[:tools], &(&1.name == "agent_module"))
      assert Enum.find(first_opts[:tools], &(&1.name == "submit_result"))

      assert_receive {LLMProvider, :request, ^model_id, second_context, _second_opts}
      assert context_contains?(second_context, inspect(ContextAgent))
    end
  end

  defp context_contains?(context, text) do
    context
    |> inspect()
    |> String.contains?(text)
  end

  defp trace_context do
    TraceContext.new(
      trace_id: "0123456789abcdef0123456789abcdef",
      span_id: "0123456789abcdef",
      baggage: "upstream=value"
    )
  end
end
