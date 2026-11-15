defmodule Condukt.Session.ViewTest do
  use ExUnit.Case, async: true

  alias Condukt.Session.View
  alias Condukt.Test.LLMProvider
  alias ReqLLM.StreamChunk
  alias ReqLLM.ToolCall

  @secret "sk-secret-1"

  defmodule Agent do
    @moduledoc false
    use Condukt
  end

  defmodule SecretRedactor do
    @moduledoc false
    @behaviour Condukt.Redactor

    @impl true
    def redact(text, _opts), do: String.replace(text, "sk-secret-1", "[REDACTED]")
  end

  defmodule ChangeRecorder do
    @moduledoc false
    @behaviour Condukt.Notifier

    @impl true
    def publish(_session_id, _event, _opts), do: :ok

    @impl true
    def publish_change(_session_id, epoch, seq, change, opts) do
      send(Keyword.fetch!(opts, :to), {:published_change, epoch, seq, change})
      :ok
    end
  end

  # A viewer that attaches while a tool runs, with steering and a follow-up
  # queued, sees all of it at once, then folds the changes after it into
  # exactly the view the session ends with.
  test "a late viewer gets the current view, then every later change once" do
    test_pid = self()
    {model, _id} = LLMProvider.model([])

    {:ok, pid} =
      Agent.start_link(
        model: model,
        api_key: "provider-key-123",
        tools: [slow_tool(test_pid, "token #{@secret} found")],
        redactor: SecretRedactor,
        notifier: {ChangeRecorder, to: test_pid},
        load_project_instructions: false
      )

    stub_streams(pid, [
      [StreamChunk.text("Looking"), StreamChunk.tool_call("slow", %{}, %{id: "call-1", index: 0})],
      [StreamChunk.text("done")],
      [StreamChunk.text("followed up")]
    ])

    stream = Task.async(fn -> pid |> Condukt.stream("go #{@secret}") |> Enum.to_list() end)
    assert_receive {:tool_running, tool}
    assert :ok = Condukt.steer(pid, "steer #{@secret}")
    assert :ok = Condukt.follow_up(pid, "then summarize")

    view = Condukt.watch(pid)

    assert [
             %{type: :user, message: %{content: "go [REDACTED]"}},
             %{type: :assistant, text: "Looking"},
             %{type: :tool, id: "call-1", name: "slow", status: :running, result: nil}
           ] = view.run.items

    assert [%{kind: :steer, message: %{content: "steer [REDACTED]"}}, %{kind: :follow_up}] = view.queue
    assert view.agent.tools == ["slow"]
    refute inspect(view) =~ "provider-key-123"

    send(tool, :continue)
    assert {:text, "done"} in Task.await(stream)
    final = await_idle(pid)

    changes = receive_changes(view.epoch, view.seq + 1, final.seq)
    folded = Enum.reduce(changes, view, fn {seq, change}, acc -> ok!(View.advance(acc, view.epoch, seq, change)) end)

    assert folded == final

    assert Enum.map(final.messages, &Condukt.Message.text/1) |> Enum.take(-3) == [
             "done",
             "then summarize",
             "followed up"
           ]

    assert Enum.any?(final.messages, &(&1.content == "token [REDACTED] found"))
    assert Enum.any?(changes, &match?({_seq, {:input, %{content: "steer [REDACTED]"}}}, &1))
    refute inspect({changes, final}) =~ @secret

    # The notifier carried the same numbered changes a remote viewer applies.
    epoch = view.epoch

    published =
      for _ <- 1..final.seq do
        assert_receive {:published_change, ^epoch, seq, change}
        {seq, change}
      end

    assert Enum.drop(published, view.seq) == changes

    GenServer.stop(pid)
  end

  test "advance tells a viewer to drop a repeat and to refetch after a gap" do
    view = %View{epoch: 7, seq: 3}

    assert {:ok, %View{seq: 4, queue: [:item]}} = View.advance(view, 7, 4, {:queue, [:item]})
    assert View.advance(view, 7, 3, {:queue, []}) == :stale
    assert View.advance(view, 7, 5, {:queue, []}) == :gap
    assert View.advance(view, 8, 4, {:queue, []}) == :gap
  end

  # A turn run without streaming publishes no events, but its running tools
  # still show in the view, and an abort ends the run there.
  test "a non-streaming turn shows its running tool, and an abort ends it" do
    test_pid = self()

    {model, _id} =
      LLMProvider.model([
        LLMProvider.response(
          %ReqLLM.Message{role: :assistant, content: [], tool_calls: [ToolCall.new("call-1", "slow", "{}")]},
          :tool_calls
        )
      ])

    {:ok, pid} =
      Agent.start_link(model: model, tools: [slow_tool(test_pid, "late")], load_project_instructions: false)

    run = Task.async(fn -> Condukt.run(pid, "go") end)
    assert_receive {:tool_running, tool}

    view = Condukt.view(pid)
    assert View.running?(view)
    assert [%{type: :user}, %{type: :tool, id: "call-1", status: :running}] = view.run.items

    assert :ok = Condukt.abort(pid)
    assert Task.await(run) == {:error, :aborted}
    send(tool, :continue)

    assert %View{run: nil, error: :aborted, messages: []} = Condukt.view(pid)

    GenServer.stop(pid)
  end

  defp slow_tool(test_pid, result) do
    Condukt.tool(
      name: "slow",
      description: "slow",
      parameters: %{type: "object", properties: %{}},
      call: fn _, _ ->
        send(test_pid, {:tool_running, self()})
        receive do: (:continue -> {:ok, result})
      end
    )
  end

  defp stub_streams(pid, scripts) do
    responses =
      Enum.map(scripts, fn chunks ->
        finish = if Enum.any?(chunks, &(&1.type == :tool_call)), do: :tool_calls, else: :stop

        metadata =
          start_supervised!({ReqLLM.StreamResponse.MetadataHandle, fn -> %{finish_reason: finish} end}, id: make_ref())

        %ReqLLM.StreamResponse{
          stream: chunks,
          metadata_handle: metadata,
          cancel: fn -> :ok end,
          model: nil,
          context: nil
        }
      end)

    responses = start_supervised!({Elixir.Agent, fn -> responses end})

    Mimic.stub(ReqLLM, :stream_text, fn model, context, _opts ->
      response = Elixir.Agent.get_and_update(responses, fn [response | rest] -> {response, rest} end)
      {:ok, %{response | model: ReqLLM.model!(model), context: context}}
    end)

    Mimic.allow(ReqLLM, self(), pid)
  end

  defp await_idle(pid, attempts \\ 200) do
    view = Condukt.view(pid)

    cond do
      not View.running?(view) and view.queue == [] and length(view.messages) == 7 -> view
      attempts == 0 -> flunk("session never settled: #{inspect(view)}")
      true -> Process.sleep(5) && await_idle(pid, attempts - 1)
    end
  end

  defp receive_changes(_epoch, first, last) when first > last, do: []

  defp receive_changes(epoch, first, last) do
    assert_receive {:condukt_change, _id, ^epoch, ^first, change}
    [{first, change} | receive_changes(epoch, first + 1, last)]
  end

  defp ok!({:ok, view}), do: view
end
