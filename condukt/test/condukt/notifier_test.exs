defmodule Condukt.NotifierTest do
  use ExUnit.Case, async: true

  alias Condukt.Notifier
  alias Condukt.Notifiers.PubSub
  alias Condukt.Session
  alias Condukt.Sessions
  alias Condukt.Test.LLMProvider

  defmodule Recorder do
    @moduledoc false
    @behaviour Condukt.Notifier

    @impl true
    def publish(session_id, event, opts) do
      # Tolerates being called without options, which is what a bare module
      # spec passes.
      if to = Keyword.get(opts, :to), do: send(to, {:published, session_id, event, opts})
      :ok
    end
  end

  defmodule Agent do
    @moduledoc false
    use Condukt.Agent

    @impl Condukt
    def model, do: "openrouter:test"
  end

  describe "dispatching a spec" do
    test "no notifier is the default and does nothing" do
      assert Notifier.publish(nil, "session", {:text, "hi"}) == :ok
    end

    test "a bare module is called with empty options" do
      assert Notifier.publish(Recorder, "session", {:text, "hi"}) == :ok
    end

    test "options are handed back on every call" do
      Notifier.publish({Recorder, to: self(), topic: "runs"}, "session-1", {:text, "hi"})

      assert_receive {:published, "session-1", {:text, "hi"}, opts}
      assert opts[:topic] == "runs"
    end
  end

  describe "inside a session" do
    setup do
      {model, _id} = LLMProvider.model([])
      metadata = start_supervised!({ReqLLM.StreamResponse.MetadataHandle, fn -> %{finish_reason: :stop} end})

      Mimic.stub(ReqLLM, :stream_text, fn model, context, _opts ->
        {:ok,
         %ReqLLM.StreamResponse{
           stream: [ReqLLM.StreamChunk.text("hello")],
           metadata_handle: metadata,
           cancel: fn -> :ok end,
           model: ReqLLM.model!(model),
           context: context
         }}
      end)

      {:ok, model: model}
    end

    # Alongside the direct subscribers, not instead of them: adding a notifier
    # must not change what an existing caller receives.
    test "an event reaches both the subscriber and the notifier", %{model: model} do
      {:ok, session} = Sessions.start(Agent, model: model, api_key: "test", notifier: {Recorder, to: self()})
      id = Session.id(session)
      on_exit(fn -> Sessions.stop(id) end)
      Mimic.allow(ReqLLM, self(), session)

      assert {:text, "hello"} in (Condukt.stream(session, "go") |> Enum.to_list())
      assert_receive {:published, ^id, {:text, "hello"}, _opts}
    end

    test "a session without one publishes nothing", %{model: model} do
      {:ok, session} = Sessions.start(Agent, model: model, api_key: "test")
      id = Session.id(session)
      on_exit(fn -> Sessions.stop(id) end)
      Mimic.allow(ReqLLM, self(), session)

      assert {:text, "hello"} in (Condukt.stream(session, "go") |> Enum.to_list())
      refute_receive {:published, _id, _event, _opts}
    end
  end

  describe "the PubSub adapter" do
    test "namespaces topics by session" do
      assert PubSub.topic("abc") == "condukt:session:abc"
      assert PubSub.topic("abc", "runs:") == "runs:abc"
    end
  end
end
