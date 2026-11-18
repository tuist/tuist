defmodule Condukt.SessionsSubmitTest do
  use ExUnit.Case, async: true

  alias Condukt.Message
  alias Condukt.Sessions
  alias Condukt.Sessions.Inbox
  alias Condukt.Sessions.Settled
  alias Condukt.Test.LLMProvider
  alias ReqLLM.StreamChunk
  alias ReqLLM.ToolCall

  # Sessions started under `Condukt.Sessions` do not inherit `$callers`, so
  # each one allows the test's ReqLLM stub itself.
  defmodule StreamAgent do
    use Condukt

    @impl true
    def init(opts) do
      Mimic.allow(ReqLLM, Keyword.fetch!(opts, :test_pid), self())
      {:ok, opts}
    end
  end

  test "input reaches a running session by id once per request id and starts a turn" do
    {model, model_id} = LLMProvider.model([])
    stub_streams(%{model_id => [stream_response([StreamChunk.text("hello")])]})
    id = start_session(model: model, inbox: nil)

    assert Sessions.submit(id, "hi", request_id: "r1") == :ok
    assert Sessions.submit(id, "hi again", request_id: "r1") == {:error, :duplicate}

    assert await_texts(id, 2) == [{:user, "hi"}, {:assistant, "hello"}]
    assert_received {:streamed, ^model_id}
    refute_receive {:streamed, ^model_id}, 50

    assert Sessions.submit("no-such-session", "hi", request_id: "r1", inbox: nil) == {:error, :not_found}
    assert Sessions.submit(id, "hi", request_id: "r2", reply_to: id) == {:error, {:invalid_option, :reply_to}}
    assert Sessions.submit(id, "hi", request_id: "r3", report: true) == {:error, :reply_needs_from}
  end

  test "a parked tool call wakes with the answer to the input it submitted" do
    {parent_model, _id} =
      LLMProvider.model([tool_call("call_1", %{"task" => "count to two"}), LLMProvider.text_response("parent done")])

    {child_model, child_model_id} = LLMProvider.model([])
    stub_streams(%{child_model_id => [stream_response(blocking_chunks(self(), "one two"))]})

    child = start_session(model: child_model, inbox: nil)
    parent = start_session(model: parent_model, inbox: nil, tools: [delegate(child)])

    run = Task.async(fn -> Condukt.Session.run(Sessions.via(parent), "go") end)

    # The child answers only once the parent's call has parked on its key.
    assert_receive {:inference, inference}, 1_000
    key = "settled-call_1"

    assert %{tool_calls: [%{signals: [{Settled, ^key}]}]} =
             await(fn -> Condukt.Session.waiting(Sessions.via(parent)) end)

    send(inference, :continue)

    assert Task.await(run) == {:ok, "parent done"}
    assert tool_result(parent, "call_1") == "child said: one two"
    assert await_texts(child, 2) == [{:user, "count to two"}, {:assistant, "one two"}]
  end

  test "aborting the target settles the input as aborted, which wakes the waiting call" do
    {parent_model, _id} =
      LLMProvider.model([tool_call("call_1", %{"task" => "count"}), LLMProvider.text_response("parent done")])

    {child_model, child_model_id} = LLMProvider.model([])
    stub_streams(%{child_model_id => [stream_response(blocking_chunks(self(), "never"))]})

    child = start_session(model: child_model, inbox: nil)
    parent = start_session(model: parent_model, inbox: nil, tools: [delegate(child)])
    run = Task.async(fn -> Condukt.Session.run(Sessions.via(parent), "go") end)

    assert_receive {:inference, inference}, 1_000
    on_exit(fn -> send(inference, :continue) end)
    await(fn -> Condukt.Session.waiting(Sessions.via(parent)) end)

    assert Sessions.abort(child) == :ok

    assert Task.await(run) == {:ok, "parent done"}
    assert tool_result(parent, "call_1") == {:error, "child stopped"}
  end

  test "an answer nobody waits for is reported to the sender as input" do
    {parent_model, parent_model_id} = LLMProvider.model([])
    {child_model, child_model_id} = LLMProvider.model([])

    stub_streams(%{
      child_model_id => [stream_response([StreamChunk.text("42")])],
      parent_model_id => [stream_response([StreamChunk.text("noted")])]
    })

    parent = start_session(model: parent_model, inbox: nil)
    child = start_session(model: child_model, inbox: nil, parent: parent)

    assert Sessions.submit(child, "the answer?", request_id: "r1", from: parent, notify: "k", report: true) == :ok

    assert await_texts(parent, 2) == [{:user, "[session #{child} answered] 42"}, {:assistant, "noted"}]
  end

  test "an abort follows the parent link only when asked to" do
    {parent_model, parent_model_id} = LLMProvider.model([])
    {child_model, child_model_id} = LLMProvider.model([])

    stub_streams(%{
      parent_model_id => [stream_response(blocking_chunks(self(), "parent"))],
      child_model_id => [stream_response(blocking_chunks(self(), "child"))]
    })

    parent = start_session(model: parent_model, inbox: nil)
    child = start_session(model: child_model, inbox: nil, parent: parent)
    child_pid = Sessions.whereis(child)
    assert Sessions.children(parent) == [{child, child_pid}]
    assert Sessions.children(child) == []

    :ok = Sessions.submit(parent, "work", request_id: "p1")
    :ok = Sessions.submit(child, "work", request_id: "c1")
    assert_receive {:inference, first}, 1_000
    assert_receive {:inference, second}, 1_000
    on_exit(fn -> Enum.each([first, second], &send(&1, :continue)) end)

    assert Sessions.abort(parent, children: false) == :ok
    refute streaming?(parent)
    assert streaming?(child)

    assert Sessions.abort(parent) == :ok
    refute streaming?(child)
    assert Sessions.whereis(child) == child_pid
    assert Sessions.abort("no-such-session") == {:error, :not_found}

    assert Sessions.stop(parent, children: true) == :ok
    assert await(fn -> not Process.alive?(child_pid) end)
  end

  test "with an inbox, input to a session that is not running is stored and resumes it" do
    inbox_name = :"inbox_#{System.unique_integer([:positive])}"
    start_supervised!({Inbox.Memory, name: inbox_name})
    {model, model_id} = LLMProvider.model([])

    stub_streams(%{
      model_id => [stream_response(blocking_chunks(self(), "first")), stream_response([StreamChunk.text("second")])]
    })

    test_pid = self()
    id = "session-#{System.unique_integer([:positive])}"

    inbox = {Inbox.Memory, name: inbox_name}

    resumer = fn session_id ->
      send(test_pid, {:resumed, session_id})
      start_session(id: session_id, model: model, inbox: inbox)
    end

    assert Sessions.submit(id, "one", request_id: "r1", inbox: inbox, resumer: resumer) == :ok
    assert_receive {:resumed, ^id}, 1_000
    assert_receive {:inference, inference}, 1_000

    # The second waits behind the first; a retry of either is refused, also
    # after the session took it.
    assert Sessions.submit(id, "two", request_id: "r2", inbox: inbox) == :ok
    assert Sessions.submit(id, "one", request_id: "r1", inbox: inbox) == {:error, :duplicate}
    refute_received {:resumed, _id}
    assert [%{kind: :input, message: %{content: "two"}}] = await(fn -> Condukt.view(Sessions.via(id)).queue end)

    send(inference, :continue)

    assert await_texts(id, 4) == [{:user, "one"}, {:assistant, "first"}, {:user, "two"}, {:assistant, "second"}]
    assert Sessions.submit(id, "two", request_id: "r2", inbox: inbox) == {:error, :duplicate}
  end

  # A host tool in miniature: submits its task to `child` and parks until the
  # turn it started settles.
  defp delegate(child) do
    Condukt.tool(
      name: "delegate",
      description: "Delegates a task",
      parameters: %{type: "object", properties: %{task: %{type: "string"}}},
      call: fn %{"task" => task}, context ->
        key = "settled-" <> context.tool_call_id

        :ok =
          Sessions.submit(child, task,
            request_id: context.tool_call_id,
            from: context.session_id,
            notify: key,
            inbox: nil
          )

        {:park, nil, signals: [{Settled, key}], timeout: to_timeout(hour: 1)}
      end,
      wake: fn
        {:signal, _key, %{outcome: {:ok, answer}}}, nil, _context -> {:ok, "child said: " <> answer}
        {:signal, _key, %{outcome: :aborted}}, nil, _context -> {:error, "child stopped"}
      end
    )
  end

  defp start_session(opts) do
    opts = Keyword.merge([test_pid: self(), system_prompt: nil, load_project_instructions: false], opts)
    {:ok, pid} = Sessions.start(StreamAgent, opts)
    id = Condukt.Session.id(pid)
    on_exit(fn -> Sessions.stop(id) end)
    id
  end

  defp streaming?(id), do: :sys.get_state(Sessions.whereis(id)).turn.streaming

  defp tool_call(id, args) do
    call = ToolCall.new(id, "delegate", JSON.encode!(args))
    LLMProvider.response(%ReqLLM.Message{role: :assistant, content: [], tool_calls: [call]}, :tool_calls)
  end

  defp tool_result(id, call_id) do
    id
    |> Sessions.via()
    |> Condukt.history()
    |> Enum.find(&(&1.role == :tool_result and &1.tool_call_id == call_id))
    |> Map.fetch!(:content)
  end

  defp await_texts(id, count) do
    texts = fn -> id |> Sessions.via() |> Condukt.history() |> Enum.map(&{&1.role, Message.text(&1)}) end
    await(fn -> length(texts.()) == count end)
    texts.()
  end

  defp await(fun, attempts \\ 400) do
    case fun.() do
      result when result in [nil, false] and attempts > 0 ->
        Process.sleep(5)
        await(fun, attempts - 1)

      result ->
        assert result
        result
    end
  end

  defp blocking_chunks(test_pid, text) do
    Stream.map([text], fn text ->
      send(test_pid, {:inference, self()})
      receive do: (:continue -> StreamChunk.text(text))
    end)
  end

  defp stub_streams(scripts) do
    test_pid = self()
    scripts = start_supervised!({Agent, fn -> scripts end}, id: make_ref())

    Mimic.stub(ReqLLM, :stream_text, fn model, context, _opts ->
      send(test_pid, {:streamed, model.id})

      response =
        Agent.get_and_update(scripts, fn scripts ->
          [response | rest] = Map.fetch!(scripts, model.id)
          {response, Map.put(scripts, model.id, rest)}
        end)

      {:ok, %{response | model: ReqLLM.model!(model), context: context}}
    end)
  end

  defp stream_response(chunks) do
    metadata =
      start_supervised!({ReqLLM.StreamResponse.MetadataHandle, fn -> %{finish_reason: :stop} end}, id: make_ref())

    %ReqLLM.StreamResponse{stream: chunks, metadata_handle: metadata, cancel: fn -> :ok end, model: nil, context: nil}
  end
end
