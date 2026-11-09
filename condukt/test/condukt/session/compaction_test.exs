defmodule Condukt.Session.CompactionTest do
  use ExUnit.Case, async: true

  alias Condukt.Compactor.ToolResultPrune
  alias Condukt.Message
  alias Condukt.Session.Compaction
  alias Condukt.SessionStore.Snapshot
  alias Condukt.Test.LLMProvider

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
end
