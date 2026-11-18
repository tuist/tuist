defmodule Condukt.AnonymousRunTest do
  use ExUnit.Case, async: true

  alias Condukt.SessionID
  alias Condukt.Test.LLMProvider
  alias ReqLLM.Message
  alias ReqLLM.ToolCall

  describe "run/2 free-form (no input, no output)" do
    test "runs an anonymous session and returns the assistant text" do
      {model, _model_id} = LLMProvider.model(LLMProvider.text_response("hello back"))

      assert {:ok, "hello back"} =
               Condukt.AnonymousRun.run("hello",
                 model: model,
                 system_prompt: "be terse"
               )
    end

    test "calls inline tools the model invokes" do
      pid = self()

      tool =
        Condukt.tool(
          name: "ping",
          description: "Sends a ping",
          parameters: %{type: "object", properties: %{msg: %{type: "string"}}, required: ["msg"]},
          call: fn %{"msg" => msg}, _ctx ->
            send(pid, {:tool_called, msg})
            {:ok, "pong"}
          end
        )

      tool_call = ToolCall.new("call_1", "ping", JSON.encode!(%{"msg" => "hi"}))

      {model, model_id} =
        LLMProvider.model([
          LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls),
          LLMProvider.text_response("done")
        ])

      assert {:ok, "done"} = Condukt.AnonymousRun.run("ping me", model: model, tools: [tool])

      assert_receive {LLMProvider, :request, ^model_id, _context, opts}
      assert Enum.any?(opts[:tools], &(&1.name == "ping"))
      assert_receive {:tool_called, "hi"}
    end

    test "delegates to an anonymous subagent registered inline" do
      tool_call = ToolCall.new("call_1", "subagent", JSON.encode!(%{"role" => "researcher", "task" => "write notes"}))

      {parent_model, parent_model_id} =
        LLMProvider.model([
          LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls),
          LLMProvider.text_response("parent done")
        ])

      {child_model, child_model_id} = LLMProvider.model(LLMProvider.text_response("field notes"))

      assert {:ok, "parent done"} =
               Condukt.AnonymousRun.run("delegate",
                 model: parent_model,
                 subagents: [
                   researcher: [
                     model: child_model,
                     system_prompt: "Write field notes."
                   ]
                 ]
               )

      assert_receive {LLMProvider, :request, ^parent_model_id, _context, parent_opts}
      assert Enum.any?(parent_opts[:tools], &(&1.name == "subagent"))

      assert_receive {LLMProvider, :request, ^child_model_id, child_context, _child_opts}
      assert Enum.any?(child_context.messages, &message_text?(&1, "write notes"))

      assert_receive {LLMProvider, :request, ^parent_model_id, _context, _parent_opts}
    end
  end

  describe "run/2 with :input (no output)" do
    test "returns text and validates input when :input_schema is given" do
      {model, model_id} = LLMProvider.model(LLMProvider.text_response("ack"))

      assert {:ok, "ack"} =
               Condukt.AnonymousRun.run("Run the task with these args.",
                 model: model,
                 input: %{repo: "tuist/condukt", pr_number: 42},
                 input_schema: %{
                   type: "object",
                   properties: %{repo: %{type: "string"}, pr_number: %{type: "integer"}},
                   required: ["repo", "pr_number"]
                 }
               )

      assert_receive {LLMProvider, :request, ^model_id, context, _opts}
      user_message = Enum.find(context.messages, &(&1.role == :user))
      assert user_message
      text = Enum.map_join(user_message.content, "", & &1.text)
      assert text =~ "tuist/condukt"
    end

    test "rejects input that does not match :input_schema" do
      assert {:error, {:invalid_input, %JSV.ValidationError{}}} =
               Condukt.AnonymousRun.run("task",
                 input: %{repo: "tuist/condukt"},
                 input_schema: %{
                   type: "object",
                   properties: %{repo: %{type: "string"}, pr_number: %{type: "integer"}},
                   required: ["repo", "pr_number"]
                 }
               )
    end

    test "rejects non-map input" do
      assert {:error, {:invalid_input, _}} = Condukt.AnonymousRun.run("task", input: "not a map")
    end
  end

  describe "run/2 structured (with :output)" do
    @output_schema %{
      type: "object",
      properties: %{
        verdict: %{type: "string", enum: ["approve", "request_changes"]},
        summary: %{type: "string"}
      },
      required: ["verdict", "summary"]
    }

    test "captures submit_result, validates output, returns atomized map" do
      submitted = %{"verdict" => "approve", "summary" => "Looks good."}

      tool_call = ToolCall.new("call_1", "submit_result", JSON.encode!(submitted))

      {model, model_id} =
        LLMProvider.model([
          LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls),
          LLMProvider.text_response("done")
        ])

      assert {:ok, %{verdict: "approve", summary: "Looks good."}} =
               Condukt.AnonymousRun.run("Decide a verdict.",
                 model: model,
                 input: %{repo: "x", pr_number: 1},
                 output: @output_schema
               )

      assert_receive {LLMProvider, :request, ^model_id, _context, opts}
      assert Enum.any?(opts[:tools], &(&1.name == "submit_result"))
    end

    test "appends submit_result alongside user-provided tools" do
      submitted = %{"verdict" => "approve", "summary" => "ok"}

      passthrough =
        Condukt.tool(
          name: "passthrough",
          description: "no-op",
          parameters: %{type: "object", properties: %{}},
          call: fn _, _ -> {:ok, "noop"} end
        )

      tool_call = ToolCall.new("call_1", "submit_result", JSON.encode!(submitted))

      {model, model_id} =
        LLMProvider.model([
          LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls),
          LLMProvider.text_response("done")
        ])

      assert {:ok, %{verdict: "approve"}} =
               Condukt.AnonymousRun.run("Decide.",
                 model: model,
                 input: %{},
                 output: @output_schema,
                 tools: [passthrough]
               )

      assert_receive {LLMProvider, :request, ^model_id, _context, opts}
      names = Enum.map(opts[:tools], & &1.name)
      assert "passthrough" in names
      assert "submit_result" in names
    end

    test "returns :no_result_submitted when the model never calls submit_result" do
      {model, _model_id} = LLMProvider.model(LLMProvider.text_response("nope"))

      assert {:error, :no_result_submitted} =
               Condukt.AnonymousRun.run("Decide.", model: model, input: %{}, output: @output_schema)
    end

    test "returns :invalid_output when the submitted value fails validation" do
      submitted = %{"verdict" => "maybe", "summary" => "Looks good."}
      tool_call = ToolCall.new("call_1", "submit_result", JSON.encode!(submitted))

      {model, _model_id} =
        LLMProvider.model([
          LLMProvider.response(%Message{role: :assistant, content: [], tool_calls: [tool_call]}, :tool_calls),
          LLMProvider.text_response("done")
        ])

      assert {:error, {:invalid_output, %JSV.ValidationError{}}} =
               Condukt.AnonymousRun.run("Decide.", model: model, input: %{}, output: @output_schema)
    end
  end

  describe "telemetry" do
    test "emits :run :start and :stop around an anonymous call" do
      handler_id = "anonymous-run-telemetry-#{inspect(make_ref())}"
      test_pid = self()

      :telemetry.attach_many(
        handler_id,
        [
          [:condukt, :run, :start],
          [:condukt, :run, :stop]
        ],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      # Use the input-validation failure path so we don't need ReqLLM mocks.
      assert {:error, {:invalid_input, _}} =
               Condukt.AnonymousRun.run("task",
                 input: %{},
                 input_schema: %{type: "object", required: ["x"], properties: %{x: %{type: "string"}}}
               )

      assert_receive {:telemetry, [:condukt, :run, :start], %{system_time: _}, %{structured?: false, input?: true}}

      assert_receive {:telemetry, [:condukt, :run, :stop], %{duration: _}, %{structured?: false, input?: true}}
    end

    test "the :run session_id is propagated to inner :agent events" do
      handler_id = "anonymous-run-session-id-#{inspect(make_ref())}"
      test_pid = self()

      # Telemetry handlers are VM-wide, so this one sees every run in the suite,
      # not only ours. The id is chosen here and the handler drops everything
      # else, which keeps concurrent async tests out of this mailbox. Learning
      # the id from the first [:condukt, :run, :start] instead would bind it to
      # whichever run happened to fire first, and a foreign run that never
      # reaches the agent span leaves the assertions below waiting forever.
      run_id = SessionID.generate()

      :telemetry.attach_many(
        handler_id,
        [
          [:condukt, :run, :start],
          [:condukt, :run, :stop],
          [:condukt, :agent, :start],
          [:condukt, :agent, :stop]
        ],
        fn event, _measurements, metadata, %{run_id: expected, test_pid: pid} ->
          if metadata[:session_id] == expected do
            send(pid, {:telemetry, event, metadata})
          end
        end,
        %{run_id: run_id, test_pid: test_pid}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {model, _model_id} = LLMProvider.model([LLMProvider.text_response("done")])

      assert {:ok, "done"} = Condukt.AnonymousRun.run("hello", model: model, id: run_id)

      assert is_binary(run_id)
      assert_receive {:telemetry, [:condukt, :run, :start], %{session_id: ^run_id}}
      assert_receive {:telemetry, [:condukt, :agent, :start], %{session_id: ^run_id}}
      assert_receive {:telemetry, [:condukt, :agent, :stop], %{session_id: ^run_id}}
      assert_receive {:telemetry, [:condukt, :run, :stop], %{session_id: ^run_id}}
    end
  end

  defp message_text?(%Message{content: content}, text) when is_list(content) do
    Enum.any?(content, fn
      %{text: ^text} -> true
      _part -> false
    end)
  end

  defp message_text?(%Message{content: text}, text) when is_binary(text), do: true
  defp message_text?(_message, _text), do: false
end
