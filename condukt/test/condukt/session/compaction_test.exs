defmodule Condukt.Session.CompactionTest do
  use ExUnit.Case, async: true

  alias Condukt.Compactor.Sliding
  alias Condukt.Compactor.ToolResultPrune
  alias Condukt.Message
  alias Condukt.Session.Compaction
  alias Condukt.SessionStore.Snapshot
  alias Condukt.Test.LLMProvider
  alias ReqLLM.Providers.Anthropic
  alias ReqLLM.Step.Error, as: StepError
  alias ReqLLM.Streaming.Failure

  defmodule TestAgent do
    use Condukt
  end

  defmodule Store do
    @behaviour Condukt.SessionStore

    def load(opts), do: {:ok, Keyword.fetch!(opts, :snapshot)}
    def save(_snapshot, _opts), do: :ok
    def clear(_opts), do: :ok
  end

  defmodule RejectingCompactor do
    def compact(_messages, _opts), do: {:error, :unavailable}
  end

  # Each call takes the next step from the `:script` agent, by default
  # summarising all but the newest message it receives. `:keep` returns the
  # history unchanged, as when its own budget still fits, and `:gate` waits
  # for `:finish` before summarising.
  defmodule SummarisingCompactor do
    def compact(messages, opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:compacting, Enum.map(messages, &Message.text/1)})
      script = opts[:script]
      step = if script, do: Agent.get_and_update(script, &Enum.split(&1, 1)), else: []

      case step do
        [:keep] ->
          {:ok, messages}

        [{:error, _reason} = error] ->
          error

        [:gate] ->
          send(test_pid, {:gated, self()})
          receive do: (:finish -> {:ok, [Message.user("summary") | Enum.take(messages, -1)]})

        _summarise ->
          {:ok, [Message.user("summary") | Enum.take(messages, -1)]}
      end
    end
  end

  @old String.duplicate("o", 2_000)

  test "compacts tool results before the next model request, not just at run completion" do
    call = ReqLLM.ToolCall.new("lookup-1", "lookup", "{}")

    {model, model_id} =
      LLMProvider.model([
        LLMProvider.response(%ReqLLM.Message{role: :assistant, content: [], tool_calls: [call]}, :tool_calls),
        LLMProvider.text_response("done")
      ])

    tool =
      Condukt.tool(
        name: "lookup",
        description: "Lookup",
        parameters: %{type: "object", properties: %{}},
        call: fn _args, _context -> {:ok, String.duplicate("large result", 1_000)} end
      )

    {:ok, pid} =
      TestAgent.start_link(
        model: model,
        tools: [tool],
        compactor: {ToolResultPrune, keep_recent: 0, max_size: 100},
        load_project_instructions: false
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    assert {:ok, "done"} = Condukt.run(pid, "find it")
    assert_receive {LLMProvider, :request, ^model_id, _first, _opts}
    assert_receive {LLMProvider, :request, ^model_id, second, _opts}
    assert inspect(second) =~ "<elided:"
    refute inspect(second) =~ String.duplicate("large result", 100)
    assert Enum.any?(second.messages, &(&1.role == :tool and &1.tool_call_id == "lookup-1"))
    assert Enum.any?(Condukt.history(pid), &(&1.role == :tool_result and String.starts_with?(&1.content, "<elided:")))
  end

  test "stream requests use compacted restored history too" do
    {model, model_id} = LLMProvider.model([])
    messages = [Message.user("find it"), Message.tool_result("previous", String.duplicate("payload", 1_000))]
    snapshot = Snapshot.new(%{id: "restored", messages: messages})

    {:ok, pid} =
      TestAgent.start_link(
        model: model,
        session_store: {Store, snapshot: snapshot},
        compactor: {ToolResultPrune, keep_recent: 0, max_size: 100},
        load_project_instructions: false
      )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    Condukt.stream(pid, "continue") |> Enum.to_list()
    assert_receive {LLMProvider, :stream_request, ^model_id, context, _opts}
    assert inspect(context) =~ "<elided:"
    refute inspect(context) =~ String.duplicate("payload", 100)
  end

  test "reports start/stop, byte reduction and no-op without exposing history" do
    owner = self()
    id = "compaction-#{System.unique_integer([:positive])}"
    metadata = %{agent: TestAgent, session_id: id}

    :telemetry.attach_many(
      id,
      [[:condukt, :compact, :start], [:condukt, :compact, :stop]],
      fn event, measures, meta, _ ->
        if meta[:session_id] == id, do: send(owner, {event, measures, meta})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
    messages = [Message.user("keep request"), Message.tool_result("one", String.duplicate("private", 1_000))]
    result = Compaction.apply({ToolResultPrune, keep_recent: 0, max_size: 100}, messages, metadata)
    assert hd(result) == hd(messages)
    assert_receive {[:condukt, :compact, :start], _, ^metadata}
    assert_receive {[:condukt, :compact, :stop], measures, %{changed: true, status: :ok} = meta}
    assert measures.before == measures.after
    assert measures.before_bytes > measures.after_bytes
    refute inspect(meta) =~ "private"
    Compaction.apply({ToolResultPrune, keep_recent: 0, max_size: 100}, result, metadata)
    assert_receive {[:condukt, :compact, :stop], _, %{changed: false}}
  end

  test "disabled and failed compactors preserve the original history" do
    messages = [Message.user("keep request")]
    assert Compaction.apply(nil, messages, %{}) == messages
    assert Compaction.apply(RejectingCompactor, messages, %{}) == messages
  end

  describe "provider context-length rejections" do
    for mode <- [:run, :stream] do
      @tag mode: mode
      @tag :capture_log
      test "#{mode} compacts and retries the rejected request once", %{mode: mode} do
        {pid, model_id} =
          overflow_session(
            if(mode == :run, do: [{:error, anthropic_overflow()}, LLMProvider.text_response("done")], else: [])
          )

        if mode == :stream do
          rejected = stream_response(Stream.map([:chunk], fn _ -> raise stream_overflow() end))
          stub_stream(pid, model_id, [rejected, stream_response([ReqLLM.StreamChunk.text("done")])])
        end

        case mode do
          :run -> assert Condukt.run(pid, "new prompt") == {:ok, "done"}
          :stream -> assert {:text, "done"} in (Condukt.stream(pid, "new prompt") |> Enum.to_list())
        end

        # Only the history before the active prompt is compacted.
        assert_receive {:compacting, [@old, "old answer"]}
        request = if mode == :run, do: :request, else: :stream_request
        assert_receive {LLMProvider, ^request, ^model_id, rejected, _}
        assert_receive {LLMProvider, ^request, ^model_id, retried, _}
        refute_receive {LLMProvider, ^request, ^model_id, _, _}, 20
        assert context_text(rejected) =~ @old
        assert context_text(retried) == "summary\nold answer\nnew prompt"
        assert Enum.map(Condukt.history(pid), &Message.text/1) == ["summary", "old answer", "new prompt", "done"]
      end
    end

    for background <- [false, true] do
      @tag background: background
      @tag :capture_log
      test "Sliding shrinks further and recovers the request (background: #{background})", %{background: background} do
        {pid, model_id} =
          overflow_session([{:error, anthropic_overflow()}, LLMProvider.text_response("done")],
            compactor: {Sliding, keep: 40},
            background_compaction: if(background, do: [context_window: 1_000_000], else: false)
          )

        id = Condukt.Session.id(pid)
        owner = self()
        handler = "overflow-#{id}"

        :telemetry.attach_many(
          handler,
          [[:condukt, :compact, :start], [:condukt, :compact, :stop]],
          fn event, _measures, meta, _ -> if meta.session_id == id, do: send(owner, {event, meta}) end,
          nil
        )

        on_exit(fn -> :telemetry.detach(handler) end)

        # Forty messages fit by Sliding's own budget, so only the overflow pass changes anything.
        assert Condukt.run(pid, "new prompt") == {:ok, "done"}
        assert_receive {LLMProvider, :request, ^model_id, rejected, _}
        assert_receive {LLMProvider, :request, ^model_id, retried, _}
        assert context_text(rejected) =~ @old

        # Only the overflow pass is tagged; the synchronous pass before each request is not.
        stops = collect_compaction_stops()
        assert [%{trigger: :overflow, changed: true}] = Enum.filter(stops, &Map.has_key?(&1, :trigger))
        assert background or Enum.any?(stops, &(not Map.has_key?(&1, :trigger)))

        # Synchronous mode slides the whole history; background mode only the prefix before the prompt.
        expected = if background, do: "old answer\nnew prompt", else: "new prompt"
        assert context_text(retried) == expected
      end
    end

    @tag :capture_log
    test "synchronous compaction retries only when a second pass changes the history" do
      script = start_supervised!({Agent, fn -> [:keep] end}, id: :script)

      {pid, model_id} =
        overflow_session([{:error, anthropic_overflow()}, LLMProvider.text_response("done")],
          compactor: {SummarisingCompactor, test_pid: self(), script: script},
          background_compaction: false
        )

      assert Condukt.run(pid, "new prompt") == {:ok, "done"}
      assert_receive {:compacting, [@old, "old answer", "new prompt"]}
      assert_receive {:compacting, [@old, "old answer", "new prompt"]}
      assert_receive {LLMProvider, :request, ^model_id, _rejected, _}
      assert_receive {LLMProvider, :request, ^model_id, retried, _}
      assert context_text(retried) == "summary\nnew prompt"
    end

    @tag :capture_log
    test "stream returns the rejection without a retry once output was emitted" do
      {pid, model_id} = overflow_session([])

      partial =
        Stream.concat([ReqLLM.StreamChunk.text("partial")], Stream.map([:chunk], fn _ -> raise stream_overflow() end))

      stub_stream(pid, model_id, [
        stream_response(partial),
        stream_response([ReqLLM.StreamChunk.text("must not retry")])
      ])

      events = Condukt.stream(pid, "new prompt") |> Enum.to_list()
      assert {:text, "partial"} in events
      assert Enum.any?(events, &match?({:error, %ReqLLM.Error.API.Stream{}}, &1))
      refute {:text, "must not retry"} in events
      assert_receive {LLMProvider, :stream_request, ^model_id, _, _}
      refute_receive {LLMProvider, :stream_request, ^model_id, _, _}, 20
      refute_received {:compacting, _}
    end

    @tag :capture_log
    test "a running background compaction is replaced by one over the largest prefix" do
      script = start_supervised!({Agent, fn -> [:gate] end}, id: :script)
      {pid, model_id} = overflow_session([], background_session(script))
      stub_stream(pid, model_id, [waiting_overflow(), stream_response([ReqLLM.StreamChunk.text("done")])])
      task = Task.async(fn -> Condukt.stream(pid, "new prompt") |> Enum.to_list() end)

      # The speculative task is still waiting when the provider rejects the request.
      assert_receive {:compacting, [@old, "old answer"]}
      assert_receive {:gated, worker}
      monitor = Process.monitor(worker)
      assert_receive {:inference, inference}, 1_000
      send(inference, :continue)

      assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
      assert_receive {:compacting, [@old, "old answer"]}
      assert {:ok, events} = Task.yield(task, 2_000)
      assert {:text, "done"} in events
      assert_receive {LLMProvider, :stream_request, ^model_id, _rejected, _}
      assert_receive {LLMProvider, :stream_request, ^model_id, retried, _}
      assert context_text(retried) == "summary\nold answer\nnew prompt"
    end

    @tag :capture_log
    test "a ready background result is retried without another compaction" do
      # A second compaction would fail, so only the adopted result can recover the request.
      script = start_supervised!({Agent, fn -> [:summarise, {:error, :unavailable}] end}, id: :script)
      {pid, model_id} = overflow_session([], background_session(script))
      stub_stream(pid, model_id, [waiting_overflow(), stream_response([ReqLLM.StreamChunk.text("done")])])
      task = Task.async(fn -> Condukt.stream(pid, "new prompt") |> Enum.to_list() end)

      assert_receive {:compacting, [@old, "old answer"]}
      assert_receive {:inference, inference}, 1_000
      await_compaction_result(pid)
      send(inference, :continue)

      assert {:ok, events} = Task.yield(task, 2_000)
      assert {:text, "done"} in events
      refute_received {:compacting, _}
      assert_receive {LLMProvider, :stream_request, ^model_id, _rejected, _}
      assert_receive {LLMProvider, :stream_request, ^model_id, retried, _}
      assert context_text(retried) == "summary\nold answer\nnew prompt"
    end

    @tag :capture_log
    test "returns the provider error when compaction cannot recover the request" do
      invalid = %ReqLLM.Error.API.Request{status: 400, reason: "messages: roles must alternate"}

      scenarios = [
        still_rejected: {[{:error, anthropic_overflow()}, {:error, anthropic_overflow()}], [], 2},
        no_compactor: {[{:error, anthropic_overflow()}], [compactor: nil, background_compaction: false], 1},
        other_rejection: {[{:error, invalid}], [], 1},
        nothing_to_compact: {[{:error, anthropic_overflow()}], [history: []], 1},
        synchronous_no_change:
          {[{:error, anthropic_overflow()}], [compactor: {ToolResultPrune, []}, background_compaction: false], 1}
      ]

      for {name, {responses, opts, requests}} <- scenarios do
        {pid, model_id} = overflow_session(responses, opts)
        {:error, expected} = List.last(responses)
        assert Condukt.run(pid, "new prompt") == {:error, expected}, "#{name}"

        for _request <- 1..requests do
          assert_receive {LLMProvider, :request, ^model_id, _, _}
        end

        refute_receive {LLMProvider, :request, ^model_id, _, _}, 20, "#{name} sent another request"
      end
    end
  end

  defp overflow_session(responses, opts \\ []) do
    {model, model_id} = LLMProvider.model(responses)
    history = Keyword.get(opts, :history, [Message.user(@old), Message.assistant("old answer")])

    defaults = [
      model: model,
      compactor: {SummarisingCompactor, test_pid: self()},
      # A window this large keeps estimates under every threshold, as when they undercount.
      background_compaction: [context_window: 1_000_000],
      session_store: {Store, snapshot: Snapshot.new(%{id: "overflow", messages: history})},
      load_project_instructions: false
    ]

    {:ok, pid} = TestAgent.start_link(Keyword.merge(defaults, Keyword.delete(opts, :history)))
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    {pid, model_id}
  end

  # Anthropic's response to an oversized buffered request, decoded by ReqLLM.
  defp anthropic_overflow do
    body =
      ~s|{"type":"error","error":{"type":"invalid_request_error",| <>
        ~s|"message":"prompt is too long: 213462 tokens > 200000 maximum"}}|

    request = Req.new(url: "https://api.anthropic.com/v1/messages")
    response = Req.Response.new(status: 400, body: body)
    {request, decoded} = Anthropic.decode_response({request, response})
    {_request, error} = StepError.handle({request, decoded})
    error
  end

  # History of about 530 estimated tokens starts background compaction at 300
  # without reaching the 900-token blocking threshold.
  defp background_session(script) do
    [
      compactor: {SummarisingCompactor, test_pid: self(), script: script},
      background_compaction: [context_window: 1_000, background_threshold: 0.3, keep_recent_tokens: 0]
    ]
  end

  # A stream that waits for `:continue` before Anthropic rejects it as too long.
  defp waiting_overflow do
    test_pid = self()

    stream_response(
      Stream.map([:chunk], fn _ ->
        send(test_pid, {:inference, self()})
        receive do: (:continue -> raise stream_overflow())
      end)
    )
  end

  defp collect_compaction_stops(acc \\ []) do
    receive do
      {[:condukt, :compact, :start], _meta} -> collect_compaction_stops(acc)
      {[:condukt, :compact, :stop], meta} -> collect_compaction_stops([meta | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp await_compaction_result(pid, attempts \\ 200) do
    cond do
      :sys.get_state(pid).compaction.result -> :ok
      attempts == 0 -> flunk("background compaction did not finish")
      true -> Process.sleep(5) && await_compaction_result(pid, attempts - 1)
    end
  end

  # What a ReqLLM stream raises when Anthropic answers with that rejection.
  defp stream_overflow do
    cause =
      Failure.api_error(
        400,
        ~s|{"type":"error","error":{"type":"invalid_request_error","message":"prompt is too long: 213462 tokens > 200000 maximum"}}|,
        []
      )

    %ReqLLM.Error.API.Stream{reason: "Stream failed: #{inspect(cause)}", cause: cause}
  end

  defp stub_stream(pid, model_id, responses) do
    test_pid = self()
    responses = start_supervised!({Agent, fn -> responses end})

    Mimic.stub(ReqLLM, :stream_text, fn model, context, opts ->
      send(test_pid, {LLMProvider, :stream_request, model_id, context, opts})
      response = Agent.get_and_update(responses, fn [response | rest] -> {response, rest} end)
      {:ok, %{response | model: ReqLLM.model!(model), context: context}}
    end)

    Mimic.allow(ReqLLM, self(), pid)
  end

  defp stream_response(chunks) do
    metadata =
      start_supervised!({ReqLLM.StreamResponse.MetadataHandle, fn -> %{finish_reason: :stop} end}, id: make_ref())

    %ReqLLM.StreamResponse{stream: chunks, metadata_handle: metadata, cancel: fn -> :ok end, model: nil, context: nil}
  end

  defp context_text(context) do
    context.messages
    |> Enum.flat_map(& &1.content)
    |> Enum.map_join("\n", &(&1.text || ""))
  end
end
