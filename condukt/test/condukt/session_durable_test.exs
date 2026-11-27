defmodule Condukt.SessionDurableTest do
  # Every test here kills a real session process partway through a run, starts
  # a new one on the same store, and checks what the new one does with the
  # run the old one died in.
  use ExUnit.Case, async: true

  alias Condukt.Message
  alias Condukt.Session.Durable
  alias Condukt.Sessions.Inbox
  alias Condukt.Sessions.Input
  alias Condukt.SessionStore.Disk
  alias Condukt.SessionStore.Memory
  alias Condukt.SessionStore.ObjectStore
  alias Condukt.SessionStore.Snapshot
  alias Condukt.Test.Images
  alias Condukt.Test.LLMProvider
  alias ReqLLM.ToolCall

  @moduletag capture_log: true

  defmodule DurableAgent do
    use Condukt
  end

  defmodule ReplaceImage do
    @behaviour Condukt.Hooks

    @impl true
    def after_tool(%{name: "replace"}, _result, _context) do
      {:replace, {:ok, %{type: :image, media_type: "image/png", data: Base.encode64(Images.png(9001, 1))}}}
    end

    def after_tool(_call, _result, _context), do: :ok
  end

  defmodule SnapshotOnlyStore do
    @behaviour Condukt.SessionStore

    @impl true
    def load(_opts), do: :not_found

    @impl true
    def save(snapshot, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:saved_snapshot, snapshot})
      :ok
    end

    @impl true
    def clear(_opts), do: :ok
  end

  # A runtime that traps exits, so stopping its worker takes the
  # supervisor's grace period.
  defmodule TrappingRuntime do
    @behaviour Condukt.AgentRuntime

    @impl true
    def run(_prompt, context, _opts) do
      Process.flag(:trap_exit, true)
      send(Keyword.fetch!(context.runtime_opts, :test_pid), {:runtime_running, self()})

      receive do
        :never -> {:ok, "unreachable"}
      end
    end
  end

  # A Memory store whose journal refuses the record kinds listed in `:fail_on`,
  # whose saves fail with `fail_save: true`, whose snapshot cannot be read
  # with `fail_load: true`, whose journal cannot be read
  # with `fail_load_journal: true`, and cannot be cleared with
  # `fail_clear_journal: true`.
  defmodule FailingStore do
    @behaviour Condukt.SessionStore

    @impl true
    def load(opts) do
      if opts[:fail_load], do: {:error, :timeout}, else: Memory.load(opts)
    end

    @impl true
    defdelegate clear(opts), to: Memory

    @impl true
    def save(snapshot, opts) do
      if opts[:fail_save], do: {:error, :db_down}, else: Memory.save(snapshot, opts)
    end

    @impl true
    def load_journal(opts) do
      if opts[:fail_load_journal], do: {:error, :timeout}, else: Memory.load_journal(opts)
    end

    @impl true
    def clear_journal(opts) do
      if opts[:fail_clear_journal], do: {:error, :eacces}, else: Memory.clear_journal(opts)
    end

    @impl true
    def append_journal(records, opts) do
      if Enum.any?(records, fn {kind, _id, _payload} -> kind in Keyword.get(opts, :fail_on, []) end),
        do: {:error, :disk_full},
        else: Memory.append_journal(records, opts)
    end
  end

  setup do
    %{key: {:durable_test, make_ref()}}
  end

  describe "prepared images" do
    @tag :tmp_dir
    test "only prepared images enter the journal and survive crash/resume without refitting", %{key: key, tmp_dir: cwd} do
      owner = self()

      {model, model_id} =
        LLMProvider.model([
          fn ->
            send(owner, :provider_waiting)
            receive do: (:finish -> LLMProvider.text_response("unreachable"))
          end
        ])

      store_opts = [path: Path.join(cwd, "images.store")]
      opts = [session_store: Disk, session_store_opts: store_opts, image_policy: Images.policy(self())]
      {:ok, pid} = start_session(key, model, [], opts)
      normal = Images.attachment()
      wide = Images.attachment(Images.png(9001, 1))
      invalid = %{media_type: "image/png", data: "%%%invalid%%%"}
      task = Task.async(fn -> Condukt.run(pid, "inspect", images: [invalid, normal, wide]) end)
      assert_receive :provider_waiting, 1000
      assert_receive {LLMProvider, :request, ^model_id, _context, _opts}
      assert {:ok, [{:run_start, _, %{message: message}}]} = Disk.load_journal(store_opts)
      assert message.content =~ "Image omitted"
      assert [first, second] = message.images
      assert first.data == normal.data
      assert second.data == Base.encode64(Images.png(2, 1))
      assert_receive {:prepared_image, _, _}
      assert_receive {:prepared_image, _, _}
      kill(pid)
      assert {:error, {:session_exit, :killed}} = Task.await(task)

      {:ok, strict} =
        start_session(key, model, [], Keyword.put(opts, :image_policy, Images.policy(self(), max_width: 1)))

      {:ok, journal} = Disk.load_journal(store_opts)
      assert {:error, :image_history_requires_repair} = Condukt.Session.resume(strict)
      assert [{:error, :image_history_requires_repair}] = Condukt.Session.resume_stream(strict) |> Enum.to_list()
      assert {:ok, ^journal} = Disk.load_journal(store_opts)
      GenServer.stop(strict)

      {model, _} = LLMProvider.model([LLMProvider.text_response("recovered"), LLMProvider.text_response("continued")])
      {:ok, resumed} = start_session(key, model, [], opts)
      assert {:ok, "recovered"} = Condukt.Session.resume(resumed)
      assert {:ok, "continued"} = Condukt.run(resumed, "text-only follow-up")
      assert hd(Condukt.history(resumed)).images == message.images
      refute_receive {:prepared_image, _, _}, 20
      assert {:ok, snapshot} = Disk.load(store_opts)
      assert hd(snapshot.messages).images == message.images
      GenServer.stop(resumed)
      [user | rest] = snapshot.messages
      [original, fitted] = user.images
      changed = %{original | data: fitted.data}
      :ok = Disk.save(%{snapshot | messages: [%{user | images: [changed, fitted]} | rest]}, store_opts)
      {model, _} = LLMProvider.model([LLMProvider.text_response("must not request")])
      {:ok, corrupted} = start_session(key, model, [], opts)
      assert {:error, :image_history_requires_repair} = Condukt.run(corrupted, "check digest")
      refute_receive {:prepared_image, _, _}, 20
    end

    test "streamed and queued inputs share preparation before persistence", %{key: key} do
      owner = self()

      tool =
        Condukt.tool(
          name: "wait",
          description: "wait",
          parameters: %{type: "object"},
          call: fn _, _ ->
            send(owner, {:waiting, self()})
            receive do: (:continue -> {:ok, "ready"})
          end
        )

      {model, model_id} =
        LLMProvider.model([
          LLMProvider.stream_response([{:tool_call, "wait-1", "wait", "{}"}]),
          LLMProvider.stream_response([{:text, "active answer"}]),
          LLMProvider.stream_response([{:text, "queued answer"}])
        ])

      {:ok, pid} = start_session(key, model, [tool], image_policy: Images.policy(self()))
      assert :ok = Condukt.follow_up(pid, "active")
      assert_receive {LLMProvider, :stream_request, ^model_id, _first, _}, 1000
      assert_receive {:waiting, worker}, 1000

      queued =
        Task.async(fn ->
          Condukt.stream(pid, "queued", images: [Images.attachment(), Images.attachment(Images.png(9001, 1))])
          |> Enum.to_list()
        end)

      await(fn -> length(:sys.get_state(pid).turn.pending) == 1 end)
      send(worker, :continue)
      assert {:text, "queued answer"} in Task.await(queued)
      settle(pid)
      assert {:ok, snapshot} = Memory.load(key: key)
      last_user = snapshot.messages |> Enum.filter(&(&1.role == :user)) |> List.last()
      assert [normal, fitted] = last_user.images
      assert normal.data == Images.attachment().data
      assert fitted.data == Base.encode64(Images.png(2, 1))
    end

    @tag :tmp_dir
    test "Read and hook-replaced tool images are prepared before their journal records", %{key: key, tmp_dir: cwd} do
      File.write!(Path.join(cwd, "wide.png"), Images.png(9001, 1))
      owner = self()

      calls = [
        ToolCall.new("read", "Read", JSON.encode!(%{path: "wide.png"})),
        ToolCall.new("replace", "replace", "{}")
      ]

      assistant = LLMProvider.response(%ReqLLM.Message{role: :assistant, content: [], tool_calls: calls}, :tool_calls)

      {model, _} =
        LLMProvider.model([
          assistant,
          fn ->
            send(owner, :tools_committed)
            receive do: (:finish -> LLMProvider.text_response("unreachable"))
          end
        ])

      tool =
        Condukt.tool(
          name: "replace",
          description: "replace",
          parameters: %{type: "object"},
          call: fn _, _ -> {:ok, "original"} end
        )

      opts = [cwd: cwd, hooks: [ReplaceImage], image_policy: Images.policy(self())]
      {:ok, pid} = start_session(key, model, [Condukt.Tools.Read, tool], opts)
      task = Task.async(fn -> Condukt.run(pid, "read") end)
      assert_receive :tools_committed, 1000
      {:ok, records} = Memory.load_journal(key: key)
      results = for {:tool_result, _, result} <- records, do: result
      assert length(results) == 2

      for result <- results do
        assert result.content.type == :image
        assert result.content.data == Base.encode64(Images.png(2, 1))
      end

      kill(pid)
      Task.await(task)
      assert_receive {:prepared_image, _, _}
      assert_receive {:prepared_image, _, _}
      {model, model_id} = LLMProvider.model([LLMProvider.text_response("read result")])
      {:ok, resumed} = start_session(key, model, [Condukt.Tools.Read, tool], opts)
      assert {:ok, "read result"} = Condukt.Session.resume(resumed)
      refute_receive {:prepared_image, _, _}, 20
      assert_receive {LLMProvider, :request, ^model_id, context, _}
      tool_messages = Enum.filter(context.messages, &(&1.role == :tool))
      assert length(tool_messages) == 2

      for message <- tool_messages do
        assert [%{type: :text, text: text}] = message.content
        assert text =~ Base.encode64(Images.png(2, 1))
        refute text =~ Base.encode64(Images.png(9001, 1))
      end
    end

    test "enabling a policy rejects legacy history without rewriting it", %{key: key} do
      {model, _} = LLMProvider.model([LLMProvider.text_response("legacy")])
      {:ok, pid} = start_session(key, model, [])
      image = Images.attachment()
      assert {:ok, "legacy"} = Condukt.run(pid, "old image", images: [image])
      history = Condukt.history(pid)
      GenServer.stop(pid)
      {model, model_id} = LLMProvider.model([LLMProvider.text_response("must not request")])

      {:ok, restored} =
        start_session(key, model, [],
          image_policy: Images.policy(self()),
          compactor: {Condukt.Compactor.Sliding, keep: 1}
        )

      assert {:error, :image_history_requires_repair} = Condukt.run(restored, "new text")
      assert Condukt.history(restored) == history
      assert {:ok, %{messages: ^history}} = Memory.load(key: key)
      assert [{:error, :image_history_requires_repair}] = Condukt.stream(restored, "new stream") |> Enum.to_list()
      settle(restored)
      assert Condukt.history(restored) == history
      assert {:ok, %{messages: ^history}} = Memory.load(key: key)
      refute_receive {LLMProvider, :request, ^model_id, _, _}, 20
      refute_receive {:prepared_image, _, _}, 20
    end
  end

  describe "an interrupted tool call" do
    test "is not run again unless its tool is replay-safe; the model is told", %{key: key} do
      test_pid = self()

      tool =
        Condukt.tool(
          name: "charge",
          description: "charges a card",
          parameters: %{type: "object", properties: %{}},
          call: fn _args, context ->
            send(test_pid, :charged)
            Process.exit(context.agent, :kill)
            {:ok, "charged"}
          end
        )

      {model, _} = LLMProvider.model([tool_call_response("call_1", "charge")])
      {:ok, pid} = start_session(key, model, [tool])

      assert {:error, {:session_exit, :killed}} = Condukt.run(pid, "charge the card")
      assert_received :charged

      {model, model_id} = LLMProvider.model([LLMProvider.text_response("I could not confirm the charge.")])
      {:ok, pid} = start_session(key, model, [tool])

      assert %{run_id: run_id, request_id: nil, restarts: 0} = Condukt.Session.interrupted(pid)
      assert is_integer(run_id)

      assert {:ok, "I could not confirm the charge."} = Condukt.Session.resume(pid)
      refute_received :charged

      assert_receive {LLMProvider, :request, ^model_id, context, _opts}
      assert inspect(context) =~ "charge was interrupted"

      assert [
               %Message{role: :user, content: "charge the card"},
               %Message{role: :assistant},
               %Message{role: :tool_result, tool_call_id: "call_1", content: {:error, interrupted}},
               %Message{role: :assistant}
             ] = Condukt.history(pid)

      assert interrupted =~ "not run again"
      assert Condukt.Session.interrupted(pid) == nil
      assert Condukt.Session.resume(pid) == {:error, :nothing_to_resume}

      # The finished run is in the snapshot and the journal is gone.
      assert Memory.load_journal(key: key) == {:ok, []}
      {:ok, pid} = start_session(key, model, [tool])
      assert length(Condukt.history(pid)) == 4
      assert Condukt.Session.interrupted(pid) == nil
    end

    # Results are stored as each call finishes. A call that finished before the
    # crash keeps its real result even though a sibling was still running.
    test "keeps the result of a call that finished while a parallel one ran", %{key: key} do
      test_pid = self()

      charge =
        Condukt.tool(
          name: "charge",
          description: "charges a card",
          parameters: %{type: "object", properties: %{}},
          call: fn _args, _context ->
            send(test_pid, :charged)
            {:ok, "charge ch_123"}
          end
        )

      slow =
        Condukt.tool(
          name: "slow",
          description: "takes a while",
          parameters: %{type: "object", properties: %{}},
          call: fn _args, context ->
            await_journal(key, &match?({:tool_result, _, %Message{tool_call_id: "call_charge"}}, &1))
            Process.exit(context.agent, :kill)
            {:ok, "never stored"}
          end
        )

      calls = [{"call_charge", "charge"}, {"call_slow", "slow"}]
      {model, _} = LLMProvider.model([tool_call_response(calls)])
      {:ok, pid} = start_session(key, model, [charge, slow])
      assert {:error, {:session_exit, :killed}} = Condukt.run(pid, "charge and wait")
      assert_received :charged

      {model, model_id} = LLMProvider.model([LLMProvider.text_response("Charged.")])
      {:ok, pid} = start_session(key, model, [charge, slow])
      assert {:ok, "Charged."} = Condukt.Session.resume(pid)
      refute_received :charged

      assert_receive {LLMProvider, :request, ^model_id, context, _opts}
      refute inspect(context) =~ "charge was interrupted"
      assert inspect(context) =~ "slow was interrupted"

      # Back in the order the model asked for them.
      assert [
               _user,
               _assistant,
               %Message{tool_call_id: "call_charge", content: "charge ch_123"},
               %Message{tool_call_id: "call_slow", content: {:error, _}},
               _answer
             ] = Condukt.history(pid)
    end

    # The policy that counts is the one the call ran under: a build that now
    # declares the tool replay-safe must not rerun a call made while it was not.
    test "is not run again when its tool was not replay-safe when it ran", %{key: key} do
      test_pid = self()

      lookup =
        Condukt.tool(
          name: "lookup",
          description: "looks something up",
          parameters: %{type: "object", properties: %{}},
          replay_safe: true,
          call: fn _args, _context ->
            send(test_pid, :looked_up)
            {:ok, "42"}
          end
        )

      prompt = Message.user("look it up")

      :ok =
        Memory.append_journal(
          [
            {:run_start, 1, %{message: prompt}},
            {:assistant, 1, Message.assistant([{:tool_call, "call_1", "lookup", %{}}])},
            {:tool_intent, 1, %{call_id: "call_1", replay_safe: false}}
          ],
          key: key
        )

      {model, _} = LLMProvider.model([LLMProvider.text_response("Could not confirm.")])
      {:ok, pid} = start_session(key, model, [lookup])

      assert {:ok, "Could not confirm."} = Condukt.Session.resume(pid)
      refute_received :looked_up

      assert [_prompt, _calls, %Message{content: {:error, "lookup was interrupted" <> _}}, _answer] =
               Condukt.history(pid)
    end

    test "runs again when its tool is replay-safe", %{key: key} do
      test_pid = self()

      killing =
        Condukt.tool(
          name: "lookup",
          description: "looks something up",
          parameters: %{type: "object", properties: %{}},
          replay_safe: true,
          call: fn _args, context ->
            Process.exit(context.agent, :kill)
            {:ok, "never stored"}
          end
        )

      {model, _} = LLMProvider.model([tool_call_response("call_1", "lookup")])
      {:ok, pid} = start_session(key, model, [killing])
      assert {:error, {:session_exit, :killed}} = Condukt.run(pid, "look it up")

      working =
        Condukt.tool(
          name: "lookup",
          description: "looks something up",
          parameters: %{type: "object", properties: %{}},
          replay_safe: true,
          call: fn _args, _context ->
            send(test_pid, :looked_up)
            {:ok, "42"}
          end
        )

      {model, _} = LLMProvider.model([LLMProvider.text_response("It is 42.")])
      {:ok, pid} = start_session(key, model, [working])

      assert {:ok, "It is 42."} = Condukt.Session.resume(pid)
      assert_received :looked_up

      assert [_user, _assistant, %Message{role: :tool_result, content: "42"}, _answer] = Condukt.history(pid)
    end
  end

  describe "an interrupted model request" do
    test "is made again, and a retry with the run's request id resumes it", %{key: key} do
      id = "durable-#{System.unique_integer([:positive])}"

      killing = fn ->
        Process.exit(Condukt.Sessions.whereis(id), :kill)
        LLMProvider.text_response("never seen")
      end

      {model, _} = LLMProvider.model([killing])
      {:ok, pid} = start_supervised_session(id, key, model)

      assert {:error, {:session_exit, :killed}} = Condukt.run(pid, "hello", request_id: "req-1")

      {model, model_id} = LLMProvider.model([LLMProvider.text_response("hi there")])
      {:ok, pid} = start_supervised_session(id, key, model)
      assert %{request_id: "req-1"} = Condukt.Session.interrupted(pid)

      # The client retrying its request finds the interrupted run rather than
      # starting a second one. The prompt is the one the run stored, so a
      # retry whose text differs shows which of the two ran.
      assert {:ok, "hi there"} = Condukt.run(pid, "hello, retried", request_id: "req-1")
      assert_receive {LLMProvider, :request, ^model_id, _context, _opts}

      assert [%Message{role: :user, content: "hello"}, %Message{role: :assistant}] = Condukt.history(pid)
    end

    test "ends the run once it keeps crashing past the restart limit", %{key: key} do
      id = "durable-#{System.unique_integer([:positive])}"

      killing = fn ->
        Process.exit(Condukt.Sessions.whereis(id), :kill)
        LLMProvider.text_response("never seen")
      end

      {model, _} = LLMProvider.model([killing, killing])

      {:ok, pid} = start_supervised_session(id, key, model, restart_limit: 1)
      assert {:error, {:session_exit, :killed}} = Condukt.run(pid, "hello")

      {:ok, pid} = start_supervised_session(id, key, model, restart_limit: 1)
      assert {:error, {:session_exit, :killed}} = Condukt.Session.resume(pid)

      {:ok, pid} = start_supervised_session(id, key, model, restart_limit: 1)
      assert %{restarts: 1} = Condukt.Session.interrupted(pid)
      assert Condukt.Session.resume(pid) == {:error, {:restart_limit, 1}}

      # The prompt stays in the history, and the session takes new work.
      assert [%Message{role: :user, content: "hello"}] = Condukt.history(pid)
      assert Condukt.Session.interrupted(pid) == nil
    end
  end

  test "a request id runs once, across restarts", %{key: key} do
    {model, model_id} = LLMProvider.model([LLMProvider.text_response("first answer")])
    {:ok, pid} = start_session(key, model, [])

    assert {:ok, "first answer"} = Condukt.run(pid, "question", request_id: "once")
    assert_receive {LLMProvider, :request, ^model_id, _context, _opts}

    # The model has no response left, so a second run would fail.
    assert {:ok, "first answer"} = Condukt.run(pid, "question", request_id: "once")
    GenServer.stop(pid)

    {:ok, pid} = start_session(key, model, [])
    assert {:ok, "first answer"} = Condukt.run(pid, "question", request_id: "once")
    refute_received {LLMProvider, :request, _, _, _}
    assert length(Condukt.history(pid)) == 2
  end

  test "a new run closes an interrupted one, keeping what it stored", %{key: key} do
    tool =
      Condukt.tool(
        name: "deploy",
        description: "deploys",
        parameters: %{type: "object", properties: %{}},
        call: fn _args, context ->
          Process.exit(context.agent, :kill)
          {:ok, "deployed"}
        end
      )

    {model, _} = LLMProvider.model([tool_call_response("call_1", "deploy")])
    {:ok, pid} = start_session(key, model, [tool])
    assert {:error, {:session_exit, :killed}} = Condukt.run(pid, "deploy", request_id: "deploy-1")

    {model, _} = LLMProvider.model([LLMProvider.text_response("hello")])
    {:ok, pid} = start_session(key, model, [tool])

    assert {:ok, "hello"} = Condukt.run(pid, "something else")

    assert [
             %Message{content: "deploy"},
             %Message{role: :assistant},
             %Message{role: :tool_result, content: {:error, _interrupted}},
             %Message{content: "something else"},
             %Message{role: :assistant}
           ] = Condukt.history(pid)

    # The abandoned request is settled; retrying it does not deploy again.
    assert Condukt.run(pid, "deploy", request_id: "deploy-1") == {:error, :interrupted}
  end

  # A run that stored its final answer but died before its end record answered
  # its request; giving it up must not record it as interrupted.
  test "a new run settles an interrupted one that stored its answer with that answer", %{key: key} do
    prompt = Message.user("question")
    answer = Message.assistant("the answer")

    :ok =
      Memory.append_journal(
        [{:run_start, 1, %{message: prompt, request_id: "q1"}}, {:assistant, 1, answer}],
        key: key
      )

    {model, _} = LLMProvider.model([LLMProvider.text_response("hello")])
    {:ok, pid} = start_session(key, model, [])
    assert %{request_id: "q1"} = Condukt.Session.interrupted(pid)

    assert {:ok, "hello"} = Condukt.run(pid, "something else")
    assert Condukt.run(pid, "question", request_id: "q1") == {:ok, "the answer"}
    assert [^prompt, ^answer, _other, _hello] = Condukt.history(pid)
  end

  # A journal is replayed only onto the history its first run started from,
  # so one left behind by another history, as after restoring an older
  # snapshot, is not merged into it.
  test "ignores a journal that does not follow the snapshot's history", %{key: key} do
    restored = [Message.user("restored"), Message.assistant("from a backup")]
    :ok = %{messages: restored} |> Snapshot.new() |> Memory.save(key: key)
    prompt = Message.user("from another history")
    base = Durable.fingerprint([Message.user("other"), Message.assistant("history")])
    :ok = Memory.append_journal([{:run_start, 1, %{message: prompt, base: base}}], key: key)

    {model, _} = LLMProvider.model([])
    {:ok, pid} = start_session(key, model, [])

    assert Condukt.Session.interrupted(pid) == nil
    assert Condukt.history(pid) == restored
    GenServer.stop(pid)

    # The same run on top of the snapshot's own history is interrupted.
    :ok = Memory.clear_journal(key: key)
    base = Durable.fingerprint(restored)
    :ok = Memory.append_journal([{:run_start, 1, %{message: prompt, base: base}}], key: key)
    {:ok, pid} = start_session(key, model, [])
    assert %{run_id: 1} = Condukt.Session.interrupted(pid)
  end

  # Clearing drops the snapshot and the journal. When the journal cannot be
  # dropped, a restart must still not bring its runs back.
  test "a cleared session does not get back a journal it could not clear", %{key: key} do
    prompt = Message.user("before clear")
    :ok = Memory.append_journal([{:run_start, 1, %{message: prompt}}], key: key)
    store = {FailingStore, fail_clear_journal: true}

    {model, _} = LLMProvider.model([])
    {:ok, pid} = start_session(key, model, [], session_store: store)
    assert %{run_id: 1} = Condukt.Session.interrupted(pid)
    assert :ok = Condukt.clear(pid)
    GenServer.stop(pid)

    {:ok, pid} = start_session(key, model, [], session_store: store)
    assert Condukt.Session.interrupted(pid) == nil
    assert Condukt.history(pid) == []
  end

  # Steering joins the run's history between rounds, so a resume keeps it.
  test "keeps steering that joined the run before it was interrupted", %{key: key} do
    test_pid = self()

    wait =
      Condukt.tool(
        name: "wait",
        description: "waits",
        parameters: %{type: "object", properties: %{}},
        call: fn _args, _context ->
          send(test_pid, {:waiting, self()})
          receive do: (:go -> {:ok, "waited"})
        end
      )

    crash =
      Condukt.tool(
        name: "crash",
        description: "kills the session",
        parameters: %{type: "object", properties: %{}},
        call: fn _args, context ->
          Process.exit(context.agent, :kill)
          {:ok, "never stored"}
        end
      )

    {model, _} = LLMProvider.model([tool_call_response("call_1", "wait"), tool_call_response("call_2", "crash")])
    {:ok, pid} = start_session(key, model, [wait, crash])
    caller = Task.async(fn -> Condukt.run(pid, "work") end)
    assert_receive {:waiting, tool}
    assert :ok = Condukt.steer(pid, "also check the logs")
    send(tool, :go)
    assert {:error, {:session_exit, :killed}} = Task.await(caller)

    {model, model_id} = LLMProvider.model([LLMProvider.text_response("done")])
    {:ok, pid} = start_session(key, model, [wait, crash])
    assert {:ok, "done"} = Condukt.Session.resume(pid)
    assert_receive {LLMProvider, :request, ^model_id, context, _opts}
    assert inspect(context) =~ "also check the logs"

    assert [
             %Message{content: "work"},
             %Message{role: :assistant},
             %Message{role: :tool_result, tool_call_id: "call_1"},
             %Message{role: :user, content: "also check the logs"},
             %Message{role: :assistant},
             %Message{role: :tool_result, tool_call_id: "call_2", content: {:error, _interrupted}},
             %Message{role: :assistant}
           ] = Condukt.history(pid)
  end

  # The snapshot of a finished run is saved before its journal is cleared. A
  # crash between the two leaves records the snapshot already covers, which
  # must not come back as a run to resume.
  test "ignores journal records of a run the snapshot already holds", %{key: key} do
    prompt = Message.user("done already")
    answer = Message.assistant("yes")

    :ok =
      %{messages: [prompt, answer]}
      |> Snapshot.new()
      |> Snapshot.put_runs(1, [])
      |> Memory.save(key: key)

    :ok = Memory.append_journal([{:run_start, 1, %{message: prompt}}, {:assistant, 1, answer}], key: key)

    {model, _} = LLMProvider.model([LLMProvider.text_response("next")])
    {:ok, pid} = start_session(key, model, [])

    assert Condukt.Session.interrupted(pid) == nil
    assert Condukt.history(pid) == [prompt, answer]

    # The next run continues the numbering rather than reusing run 1.
    assert {:ok, "next"} = Condukt.run(pid, "again")
    settle(pid)
    assert {:ok, snapshot} = Memory.load(key: key)
    assert {2, _requests} = Snapshot.runs(snapshot)
  end

  describe "a streamed run" do
    test "is resumed after the process dies mid-response", %{key: key} do
      {model, _} = LLMProvider.model([LLMProvider.stream_response([{:text, "Let me "}, :hold])])
      {:ok, pid} = start_session(key, model, [])

      # The first chunk reaches the subscriber; the response never completes.
      assert {:text, "Let me "} = stream_until(pid, "hello", [request_id: "s1"], &match?({:text, _}, &1))

      # The request stops with the session: its worker and the stream
      # processes linked to it go down.
      worker = :sys.get_state(pid).turn.worker
      {:links, linked} = Process.info(worker, :links)
      refs = Enum.map([worker | linked], &Process.monitor/1)
      kill(pid)
      for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _pid, _reason}, 1_000)

      {model, model_id} = LLMProvider.model([LLMProvider.text_response("Let me help.")])
      {:ok, pid} = start_session(key, model, [])
      assert %{request_id: "s1"} = Condukt.Session.interrupted(pid)
      assert Condukt.history(pid) == []

      assert {:ok, "Let me help."} = Condukt.run(pid, "hello", request_id: "s1")
      assert_receive {LLMProvider, :request, ^model_id, _context, _opts}
      assert [%Message{role: :user, content: "hello"}, %Message{role: :assistant}] = Condukt.history(pid)
    end

    # Whether the reader runs the stream to its end or stops at the error.
    test "ends its stream when the session dies", %{key: key} do
      test_pid = self()

      for {consume, last} <- [
            {&Enum.to_list/1, {:error, {:session_exit, :killed}}},
            {&Enum.take_while(&1, fn event -> not match?({:error, _}, event) end), {:text, "Let me "}}
          ] do
        {model, _} = LLMProvider.model([LLMProvider.stream_response([{:text, "Let me "}, :hold])])
        {:ok, pid} = start_session(key, model, [])

        reader =
          Task.async(fn ->
            pid
            |> Condukt.stream("hello")
            |> Stream.each(&send(test_pid, {:event, &1}))
            |> consume.()
          end)

        assert_receive {:event, {:text, "Let me "}}, 5_000
        kill(pid)
        assert List.last(Task.await(reader)) == last
        Memory.clear_journal(key: key)
      end
    end

    test "keeps a streamed tool round, and does not rerun a call it interrupted", %{key: key} do
      test_pid = self()

      tool =
        Condukt.tool(
          name: "charge",
          description: "charges a card",
          parameters: %{type: "object", properties: %{}},
          call: fn _args, context ->
            send(test_pid, :charged)
            Process.exit(context.agent, :kill)
            {:ok, "charged"}
          end
        )

      response = LLMProvider.stream_response([{:text, "Charging."}, {:tool_call, "call_1", "charge", %{}}])
      {model, model_id} = LLMProvider.model([response])
      {:ok, pid} = start_session(key, model, [tool])
      ref = Process.monitor(pid)

      assert {:tool_call, "charge", "call_1", %{}} =
               stream_until(pid, "charge the card", [], &match?({:tool_call, _, _, _}, &1))

      assert_received {LLMProvider, :stream_request, ^model_id, _context, _opts}

      # Subscribers see the call only once the response asking for it is stored.
      {:ok, records} = Memory.load_journal(key: key)
      assert Enum.any?(records, &match?({:assistant, _, %Message{}}, &1))

      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
      assert_received :charged

      {model, model_id} = LLMProvider.model([LLMProvider.text_response("I could not confirm the charge.")])
      {:ok, pid} = start_session(key, model, [tool])

      assert {:ok, "I could not confirm the charge."} = Condukt.Session.resume(pid)
      refute_received :charged
      assert_receive {LLMProvider, :request, ^model_id, context, _opts}
      assert inspect(context) =~ "charge was interrupted"

      assert [_user, assistant, %Message{role: :tool_result, content: {:error, _}}, _answer] = Condukt.history(pid)
      assert Message.text(assistant) == "Charging."
      assert [{"call_1", "charge", %{}}] = Message.tool_calls(assistant)
    end
  end

  describe "a streamed resume" do
    test "continues a run when a stream retries its request id", %{key: key} do
      prompt = Message.user("hello")
      :ok = Memory.append_journal([{:run_start, 1, %{message: prompt, request_id: "s1"}}], key: key)

      {model, model_id} = LLMProvider.model([LLMProvider.stream_response([{:text, "Hi "}, {:text, "there."}])])
      {:ok, pid} = start_session(key, model, [])

      events = pid |> Condukt.stream("hello, retried", request_id: "s1") |> Enum.to_list()

      assert {:text, "Hi "} in events
      assert {:text, "there."} in events
      assert_received {LLMProvider, :stream_request, ^model_id, _context, _opts}

      # The stored prompt, not the retry's, and only once.
      assert [^prompt, %Message{role: :assistant} = answer] = Condukt.history(pid)
      assert Message.text(answer) == "Hi there."
      assert Condukt.Session.interrupted(pid) == nil
      assert Memory.load_journal(key: key) == {:ok, []}
    end

    test "emits the tool results it decides before the run goes on", %{key: key} do
      test_pid = self()

      lookup =
        Condukt.tool(
          name: "lookup",
          description: "looks something up",
          parameters: %{type: "object", properties: %{}},
          replay_safe: true,
          call: fn _args, _context ->
            send(test_pid, :looked_up)
            {:ok, "42"}
          end
        )

      charge =
        Condukt.tool(
          name: "charge",
          description: "charges a card",
          parameters: %{type: "object", properties: %{}},
          call: fn _args, _context ->
            send(test_pid, :charged)
            {:ok, "charged"}
          end
        )

      prompt = Message.user("look up and charge")

      calls =
        Message.assistant([{:tool_call, "call_lookup", "lookup", %{}}, {:tool_call, "call_charge", "charge", %{}}])

      :ok =
        Memory.append_journal(
          [
            {:run_start, 1, %{message: prompt}},
            {:assistant, 1, calls},
            {:tool_intent, 1, %{call_id: "call_lookup", replay_safe: true}},
            {:tool_intent, 1, %{call_id: "call_charge", replay_safe: false}}
          ],
          key: key
        )

      {model, _} = LLMProvider.model([LLMProvider.stream_response([{:text, "Done."}])])
      {:ok, pid} = start_session(key, model, [lookup, charge])

      events = pid |> Condukt.Session.resume_stream() |> Enum.to_list()

      assert List.first(events) == :agent_start
      assert List.last(events) == :agent_end

      # Every result follows its call, interrupted ones included, and all of
      # them come before the model continues.
      position = fn match? -> Enum.find_index(events, match?) end
      lookup_call = position.(&(&1 == {:tool_call, "lookup", "call_lookup", %{}}))
      lookup_result = position.(&(&1 == {:tool_result, "call_lookup", "42"}))
      charge_call = position.(&(&1 == {:tool_call, "charge", "call_charge", %{}}))
      charge_result = position.(&match?({:tool_result, "call_charge", {:error, "charge was interrupted" <> _}}, &1))
      answer = position.(&(&1 == {:text, "Done."}))

      assert lookup_call < lookup_result and lookup_result < answer
      assert charge_call < charge_result and charge_result < answer

      assert_received :looked_up
      refute_received :charged

      assert [
               ^prompt,
               ^calls,
               %Message{tool_call_id: "call_lookup", content: "42"},
               %Message{tool_call_id: "call_charge", content: {:error, _}},
               %Message{role: :assistant}
             ] = Condukt.history(pid)
    end

    test "delivers an answer that was stored but never delivered", %{key: key} do
      prompt = Message.user("hello")
      answer = Message.assistant("Stored answer.")
      :ok = Memory.append_journal([{:run_start, 1, %{message: prompt}}, {:assistant, 1, answer}], key: key)

      {model, model_id} = LLMProvider.model([])
      {:ok, pid} = start_session(key, model, [])

      assert [:agent_start, {:text, "Stored answer."}, :agent_end] =
               pid |> Condukt.Session.resume_stream() |> Enum.to_list()

      refute_received {LLMProvider, _, ^model_id, _, _}
      assert Condukt.history(pid) == [prompt, answer]
    end

    test "keeps what it stored when the resumed run fails", %{key: key} do
      lookup =
        Condukt.tool(
          name: "lookup",
          description: "looks something up",
          parameters: %{type: "object", properties: %{}},
          replay_safe: true,
          call: fn _args, _context -> {:ok, "42"} end
        )

      prompt = Message.user("look it up")

      :ok =
        Memory.append_journal(
          [
            {:run_start, 1, %{message: prompt}},
            {:assistant, 1, Message.assistant([{:tool_call, "call_1", "lookup", %{}}])},
            {:tool_intent, 1, %{call_id: "call_1", replay_safe: true}}
          ],
          key: key
        )

      # No scripted stream: the request after the tool round fails.
      {model, _} = LLMProvider.model([])
      {:ok, pid} = start_session(key, model, [lookup], retry: false)

      events = pid |> Condukt.Session.resume_stream() |> Enum.to_list()

      assert {:tool_result, "call_1", "42"} in events
      assert Enum.any?(events, &match?({:error, _}, &1))
      assert [^prompt, _assistant, %Message{role: :tool_result, content: "42"}] = Condukt.history(pid)
      assert Condukt.Session.interrupted(pid) == nil
    end

    test "a retry of a finished request gets its outcome without running again", %{key: key} do
      {model, model_id} = LLMProvider.model([LLMProvider.stream_response([{:text, "first"}])])
      {:ok, pid} = start_session(key, model, [])

      assert {:text, "first"} in (pid |> Condukt.stream("q", request_id: "once") |> Enum.to_list())
      assert_received {LLMProvider, :stream_request, ^model_id, _context, _opts}

      assert [{:text, "first"}] = pid |> Condukt.stream("q", request_id: "once") |> Enum.to_list()
      refute_received {LLMProvider, _, ^model_id, _, _}
      assert length(Condukt.history(pid)) == 2
      assert Condukt.run(pid, "q", request_id: "once") == {:ok, "first"}
    end

    # Compaction may replace the history at the resumed run's first checkpoint,
    # and a run that fails afterwards must not bring back what it dropped.
    test "keeps the compacted history when the resumed run fails", %{key: key} do
      lookup =
        Condukt.tool(
          name: "lookup",
          description: "looks something up",
          parameters: %{type: "object", properties: %{}},
          replay_safe: true,
          call: fn _args, _context -> {:ok, "42"} end
        )

      old = [Message.user(String.duplicate("o", 8_000)), Message.assistant("old answer")]
      :ok = Memory.save(Snapshot.new(%{messages: old}), key: key)
      prompt = Message.user("look it up")

      :ok =
        Memory.append_journal(
          [
            {:run_start, 1, %{message: prompt}},
            {:assistant, 1, Message.assistant([{:tool_call, "call_1", "lookup", %{}}])},
            {:tool_intent, 1, %{call_id: "call_1", replay_safe: true}}
          ],
          key: key
        )

      {model, _} = LLMProvider.model([])

      {:ok, pid} =
        start_session(key, model, [lookup],
          retry: false,
          compactor: {Condukt.Compactor.Sliding, keep: 0},
          background_compaction: [context_window: 1_000]
        )

      events = pid |> Condukt.Session.resume_stream() |> Enum.to_list()

      assert Enum.any?(events, &match?({:error, _}, &1))
      history = Condukt.history(pid)
      refute Enum.any?(old, &(&1 in history))
      assert [^prompt, _assistant, %Message{role: :tool_result, content: "42"}] = history
    end

    for mode <- [:resume, :resume_stream] do
      test "#{mode} keeps what the interrupted run stored when it is aborted", %{key: key} do
        test_pid = self()

        wait =
          Condukt.tool(
            name: "wait",
            description: "waits",
            parameters: %{type: "object", properties: %{}},
            replay_safe: true,
            call: fn _args, _context ->
              send(test_pid, {:waiting, self()})

              receive do
                :release -> {:ok, "done"}
              end
            end
          )

        prompt = Message.user("charge and wait")
        calls = Message.assistant([{:tool_call, "call_charge", "charge", %{}}, {:tool_call, "call_wait", "wait", %{}}])
        charged = Message.tool_result("call_charge", "charged ch_1")

        :ok =
          Memory.append_journal(
            [
              {:run_start, 1, %{message: prompt}},
              {:assistant, 1, calls},
              {:tool_intent, 1, %{call_id: "call_charge", replay_safe: false}},
              {:tool_result, 1, charged},
              {:tool_intent, 1, %{call_id: "call_wait", replay_safe: true}}
            ],
            key: key
          )

        {model, _} = LLMProvider.model([])
        {:ok, pid} = start_session(key, model, [wait])

        resumed =
          case unquote(mode) do
            :resume -> Task.async(fn -> Condukt.Session.resume(pid) end)
            :resume_stream -> Task.async(fn -> pid |> Condukt.Session.resume_stream() |> Enum.to_list() end)
          end

        assert_receive {:waiting, tool_pid}
        assert :ok = Condukt.abort(pid)

        case Task.await(resumed) do
          events when is_list(events) -> assert List.last(events) == {:error, :aborted}
          result -> assert result == {:error, :aborted}
        end

        send(tool_pid, :release)

        assert [^prompt, ^calls, ^charged, %Message{tool_call_id: "call_wait", content: {:error, _}}] =
                 Condukt.history(pid)

        assert Memory.load_journal(key: key) == {:ok, []}
        GenServer.stop(pid)

        {:ok, pid} = start_session(key, model, [wait])
        assert Condukt.Session.interrupted(pid) == nil
        assert [^prompt, ^calls, ^charged, %Message{tool_call_id: "call_wait"}] = Condukt.history(pid)
      end
    end

    test "reports why it cannot resume", %{key: key} do
      {model, _} = LLMProvider.model([])
      {:ok, pid} = start_session(key, model, [])

      assert [{:error, :nothing_to_resume}] = pid |> Condukt.Session.resume_stream() |> Enum.to_list()
      GenServer.stop(pid)

      prompt = Message.user("crashes every time")
      :ok = Memory.append_journal([{:run_start, 1, %{message: prompt}}, {:resume, 1, nil}], key: key)
      {:ok, pid} = start_session(key, model, [], restart_limit: 1)

      assert [{:error, {:restart_limit, 1}}] = pid |> Condukt.Session.resume_stream() |> Enum.to_list()
      assert Condukt.Session.interrupted(pid) == nil
      assert Condukt.history(pid) == [prompt]
    end
  end

  describe "a journal the store cannot write" do
    test "keeps a tool from running when its intent cannot be stored", %{key: key} do
      test_pid = self()

      tool =
        Condukt.tool(
          name: "charge",
          description: "charges a card",
          parameters: %{type: "object", properties: %{}},
          call: fn _args, _context ->
            send(test_pid, :charged)
            {:ok, "charged"}
          end
        )

      {model, _} =
        LLMProvider.model([tool_call_response("call_1", "charge"), LLMProvider.text_response("Could not charge.")])

      {:ok, pid} = start_session(key, model, [tool], session_store: {FailingStore, fail_on: [:tool_intent]})

      assert {:ok, "Could not charge."} = Condukt.run(pid, "charge the card")
      refute_received :charged

      assert [_user, _assistant, %Message{role: :tool_result, content: {:error, not_run}}, _answer] =
               Condukt.history(pid)

      assert not_run =~ "charge was not run"
    end

    test "fails a run whose prompt cannot be stored", %{key: key} do
      {model, model_id} = LLMProvider.model([LLMProvider.text_response("never")])
      {:ok, pid} = start_session(key, model, [], session_store: {FailingStore, fail_on: [:run_start]})

      assert {:error, {:journal_failed, :disk_full}} = Condukt.run(pid, "hello")
      refute_received {LLMProvider, :request, ^model_id, _, _}
    end

    # The resume record is what counts restarts. A resume that cannot store it
    # does not run, or a run that keeps crashing could never reach the limit.
    test "refuses a resume whose restart cannot be counted", %{key: key} do
      prompt = Message.user("hello")
      :ok = Memory.append_journal([{:run_start, 1, %{message: prompt}}], key: key)

      {model, _} = LLMProvider.model([LLMProvider.text_response("hi")])
      {:ok, pid} = start_session(key, model, [], session_store: {FailingStore, fail_on: [:resume]})

      assert {:error, {:journal_failed, :disk_full}} = Condukt.Session.resume(pid)
      assert %{run_id: 1} = Condukt.Session.interrupted(pid)
    end
  end

  # A run nobody owns must not go on: its tools would keep running and its
  # provider request would stay open.
  for mode <- [:run, :stream], stop <- [:session_dies, :aborted] do
    test "a #{mode} stops when it is #{stop}", %{key: key} do
      test_pid = self()

      tool =
        Condukt.tool(
          name: "block",
          description: "blocks",
          parameters: %{type: "object", properties: %{}},
          call: fn _args, _context ->
            send(test_pid, {:tool_running, self()})

            receive do
              :never -> {:ok, "unreachable"}
            end
          end
        )

      response =
        case unquote(mode) do
          :run -> tool_call_response("call_1", "block")
          :stream -> LLMProvider.stream_response([{:tool_call, "call_1", "block", %{}}])
        end

      {model, _} = LLMProvider.model([response])
      {:ok, pid} = start_session(key, model, [tool])

      Task.start(fn ->
        case unquote(mode) do
          :run -> Condukt.run(pid, "block")
          :stream -> pid |> Condukt.stream("block") |> Enum.to_list()
        end
      end)

      assert_receive {:tool_running, tool_pid}, 5_000
      tool_ref = Process.monitor(tool_pid)

      case unquote(stop) do
        :session_dies -> kill(pid)
        :aborted -> assert :ok = Condukt.abort(pid)
      end

      assert_receive {:DOWN, ^tool_ref, :process, ^tool_pid, _reason}, 1_000
    end
  end

  # A worker can die without reporting, here because a tool exits it. Tools
  # run in their own processes, so the tool exits the turn's worker itself. The
  # session must answer the caller and take new runs, and a journaled run is
  # left interrupted, as if the whole process had died.
  describe "a run whose worker exits" do
    setup do
      tool =
        Condukt.tool(
          name: "crash",
          description: "exits",
          parameters: %{type: "object", properties: %{}},
          call: fn _args, context -> exit_worker(context, :boom) end
        )

      %{tool: tool}
    end

    test "is left interrupted, to resume", %{key: key, tool: tool} do
      {model, _} =
        LLMProvider.model([
          LLMProvider.text_response("earlier"),
          tool_call_response("call_1", "crash"),
          LLMProvider.text_response("It crashed."),
          LLMProvider.text_response("next")
        ])

      {:ok, pid} = start_session(key, model, [tool])
      assert {:ok, "earlier"} = Condukt.run(pid, "before")
      earlier = Condukt.history(pid)

      assert {:error, {:turn_crashed, _reason}} = Condukt.run(pid, "crash it", request_id: "c")
      assert %{request_id: "c"} = Condukt.Session.interrupted(pid)
      assert Condukt.history(pid) == earlier

      # A retry of its request resumes it; the crashed call is not run again.
      assert {:ok, "It crashed."} = Condukt.run(pid, "crash it", request_id: "c")

      assert [
               _before,
               _earlier,
               %Message{content: "crash it"},
               _calls,
               %Message{content: {:error, "crash was interrupted" <> _}},
               _answer
             ] = Condukt.history(pid)

      assert {:ok, "next"} = Condukt.run(pid, "next")
    end

    # A replay-safe tool that exits its worker every time reruns on each
    # resume, until the session's restart limit ends the run.
    test "keeps counting restarts until the limit", %{key: key} do
      crash =
        Condukt.tool(
          name: "crash",
          description: "exits",
          parameters: %{type: "object", properties: %{}},
          replay_safe: true,
          call: fn _args, context -> exit_worker(context, :boom) end
        )

      {model, _} = LLMProvider.model([tool_call_response("call_1", "crash")])
      {:ok, pid} = start_session(key, model, [crash], restart_limit: 1)

      assert {:error, {:turn_crashed, _}} = Condukt.run(pid, "crash it")
      assert %{restarts: 0} = Condukt.Session.interrupted(pid)
      assert {:error, {:turn_crashed, _}} = Condukt.Session.resume(pid)
      assert %{restarts: 1} = Condukt.Session.interrupted(pid)
      assert {:error, {:restart_limit, 1}} = Condukt.Session.resume(pid)
      assert Condukt.Session.interrupted(pid) == nil
    end

    test "reports its exit reason without the session's secrets" do
      leak =
        Condukt.tool(
          name: "leak",
          description: "exits with a secret",
          parameters: %{type: "object", properties: %{}},
          call: fn _args, context -> exit_worker(context, {:leaked, "secret-token"}) end
        )

      {model, _} = LLMProvider.model([tool_call_response("call_1", "leak")])

      {:ok, pid} =
        Condukt.Session.start(DurableAgent,
          model: model,
          tools: [leak],
          secrets: [GH_TOKEN: {:static, "secret-token"}],
          load_project_instructions: false
        )

      assert {:error, {:turn_crashed, reason}} = Condukt.run(pid, "leak it")
      assert reason =~ "leaked"
      refute reason =~ "secret-token"
    end

    test "ends a stream and fails a run without a journal", %{tool: tool} do
      {model, _} =
        LLMProvider.model([
          LLMProvider.stream_response([{:tool_call, "call_1", "crash", %{}}]),
          tool_call_response("call_2", "crash"),
          LLMProvider.text_response("still here")
        ])

      {:ok, pid} =
        Condukt.Session.start(DurableAgent, model: model, tools: [tool], load_project_instructions: false)

      events = pid |> Condukt.stream("crash it") |> Enum.to_list()
      assert {:error, {:turn_crashed, _reason}} = List.last(events)
      assert {:error, {:turn_crashed, _reason}} = Condukt.run(pid, "crash it again")
      assert Condukt.Session.interrupted(pid) == nil
      assert {:ok, "still here"} = Condukt.run(pid, "hello")
    end
  end

  # A worker that traps exits is killed after the supervisor's grace period,
  # but the session does not wait for that before answering.
  # A worker that traps exits is killed after a short grace period. Neither
  # the abort nor the run started next waits long for it, and the session
  # keeps answering meanwhile.
  test "abort does not wait for a worker that traps exits", %{key: key} do
    {model, _} = LLMProvider.model([])
    {:ok, pid} = start_session(key, model, [], runtime: {TrappingRuntime, test_pid: self()}, session_store: nil)

    Task.start(fn -> Condukt.run(pid, "go") end)
    assert_receive {:runtime_running, worker}, 5_000
    ref = Process.monitor(worker)

    {abort_micros, :ok} = :timer.tc(fn -> Condukt.abort(pid) end)
    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}, 1_000

    Task.start(fn -> Condukt.run(pid, "again") end)
    assert_receive {:runtime_running, next_worker}, 5_000
    next_ref = Process.monitor(next_worker)
    assert :ok = Condukt.abort(pid)
    Task.start(fn -> Condukt.run(pid, "once more") end)
    {history_micros, _history} = :timer.tc(fn -> Condukt.history(pid) end)

    assert abort_micros < 500_000
    assert history_micros < 500_000
    assert_receive {:DOWN, ^next_ref, :process, ^next_worker, :killed}, 1_000
  end

  # A compactor without a background policy runs over the whole history at
  # every checkpoint. Its result is recomputed on resume, not journaled, so
  # the journal does not grow by the whole history every round.
  test "does not journal a compaction recomputed every round", %{key: key} do
    test_pid = self()

    lookup =
      Condukt.tool(
        name: "lookup",
        description: "looks something up",
        parameters: %{type: "object", properties: %{}},
        call: fn %{}, _context ->
          {:ok, records} = Memory.load_journal(key: key)
          send(test_pid, {:journal_kinds, Enum.map(records, &elem(&1, 0))})
          {:ok, String.duplicate("r", 200)}
        end
      )

    rounds = for n <- 1..4, do: tool_call_response("call_#{n}", "lookup")
    {model, _} = LLMProvider.model(rounds ++ [LLMProvider.text_response("done")])

    {:ok, pid} =
      start_session(key, model, [lookup], compactor: {Condukt.Compactor.ToolResultPrune, keep_recent: 1, max_size: 10})

    assert {:ok, "done"} = Condukt.run(pid, "look it up four times")

    kinds =
      for _round <- 1..4 do
        assert_receive {:journal_kinds, kinds}
        kinds
      end

    assert Enum.any?(List.flatten(kinds), &(&1 == :tool_result))
    refute Enum.any?(List.flatten(kinds), &(&1 == :messages))
  end

  # A failed run's outcome is stored as text: a raw error can hold structs a
  # fresh VM cannot decode, and a provider error holds the conversation.
  test "stores a failed request's outcome as text", %{key: key} do
    error =
      {:error, %ReqLLM.Error.API.Request{status: 400, reason: "bad request", request_body: "the whole conversation"}}

    {model, model_id} = LLMProvider.model([error])
    {:ok, pid} = start_session(key, model, [], retry: false)

    assert {:error, %ReqLLM.Error.API.Request{}} = Condukt.run(pid, "fail", request_id: "f")
    assert {:error, stored} = Condukt.run(pid, "fail", request_id: "f")
    assert is_binary(stored) and stored =~ "bad request"
    refute stored =~ "the whole conversation"
    assert_received {LLMProvider, :request, ^model_id, _, _}
    refute_received {LLMProvider, :request, ^model_id, _, _}

    settle(pid)
    assert {:ok, snapshot} = Memory.load(key: key)
    assert {_last_run_id, [{"f", {:error, ^stored}}]} = Snapshot.runs(snapshot)
  end

  test "interrupted/1 reports a session that is gone", %{key: key} do
    {model, _} = LLMProvider.model([])
    {:ok, pid} = start_session(key, model, [])
    kill(pid)
    assert {:error, {:session_exit, _reason}} = Condukt.Session.interrupted(pid)
  end

  test "does not start on a journal it cannot read", %{key: key} do
    :ok = Memory.append_journal([{:run_start, 1, %{message: Message.user("unfinished")}}], key: key)
    {model, _} = LLMProvider.model([])

    assert {:error, {:journal_load_failed, :timeout}} =
             start_session(key, model, [], session_store: {FailingStore, fail_load_journal: true})

    # Starting over would let the next save replace the stored history.
    assert {:error, {:snapshot_load_failed, :timeout}} =
             start_session(key, model, [], session_store: {FailingStore, fail_load: true})

    {:ok, pid} = start_session(key, model, [])
    assert %{run_id: 1} = Condukt.Session.interrupted(pid)
  end

  # The run ended, but its snapshot did not save, so only the journal knows
  # how. A restart must not take it for interrupted and run its request again.
  test "an ended run whose snapshot failed to save is not resumed", %{key: key} do
    test_pid = self()

    wait =
      Condukt.tool(
        name: "wait",
        description: "waits",
        parameters: %{type: "object", properties: %{}},
        call: fn _args, _context ->
          send(test_pid, {:waiting, self()})

          receive do
            :release -> {:ok, "done"}
          end
        end
      )

    {model, _} = LLMProvider.model([tool_call_response("call_1", "wait")])
    {:ok, pid} = start_session(key, model, [wait], session_store: {FailingStore, fail_save: true})

    run = Task.async(fn -> Condukt.run(pid, "wait", request_id: "R") end)
    assert_receive {:waiting, tool_pid}
    assert :ok = Condukt.abort(pid)
    assert Task.await(run) == {:error, :aborted}
    send(tool_pid, :release)
    settle(pid)
    kill(pid)

    {model, model_id} = LLMProvider.model([LLMProvider.text_response("ran again")])
    {:ok, pid} = start_session(key, model, [wait])

    assert Condukt.Session.interrupted(pid) == nil
    assert Condukt.run(pid, "wait", request_id: "R") == {:error, :aborted}
    refute_received {LLMProvider, _, ^model_id, _, _}
  end

  # A run whose snapshot failed to save keeps its journal, and the next run
  # appends after it. If that next run is then interrupted, the earlier run
  # must still reach the history, and its request id must not run again.
  test "keeps a finished run whose snapshot failed to save", %{key: key} do
    first = Message.user("first")
    first_answer = Message.assistant("first answer")
    second = Message.user("second")

    :ok =
      Memory.append_journal(
        [
          {:run_start, 1, %{message: first, request_id: "r1"}},
          {:assistant, 1, first_answer},
          {:run_start, 2, %{message: second}}
        ],
        key: key
      )

    {model, model_id} = LLMProvider.model([LLMProvider.text_response("second answer")])
    {:ok, pid} = start_session(key, model, [])

    assert Condukt.history(pid) == [first, first_answer]
    assert %{run_id: 2} = Condukt.Session.interrupted(pid)
    assert {:ok, "first answer"} = Condukt.run(pid, "first", request_id: "r1")
    refute_received {LLMProvider, :request, ^model_id, _, _}

    assert {:ok, "second answer"} = Condukt.Session.resume(pid)
    assert [^first, ^first_answer, ^second, %Message{role: :assistant}] = Condukt.history(pid)
    settle(pid)
    assert {:ok, %{messages: [_, _, _, _]} = snapshot} = Memory.load(key: key)
    assert {2, _requests} = Snapshot.runs(snapshot)
  end

  # Compaction runs only between rounds, so a history it replaced holds no
  # unfinished round, even when it dropped the last one's results.
  test "does not rerun a round that compaction replaced", %{key: key} do
    test_pid = self()

    lookup =
      Condukt.tool(
        name: "lookup",
        description: "looks something up",
        parameters: %{type: "object", properties: %{}},
        replay_safe: true,
        call: fn _args, _context ->
          send(test_pid, :looked_up)
          {:ok, "42"}
        end
      )

    prompt = Message.user("look it up")
    call = Message.assistant([{:tool_call, "call_1", "lookup", %{}}])

    :ok =
      Memory.append_journal(
        [
          {:run_start, 1, %{message: prompt}},
          {:assistant, 1, call},
          {:tool_intent, 1, %{call_id: "call_1", replay_safe: true}},
          {:tool_result, 1, Message.tool_result("call_1", "42")},
          {:messages, 1, [prompt]}
        ],
        key: key
      )

    {model, model_id} = LLMProvider.model([LLMProvider.text_response("It is 42.")])
    {:ok, pid} = start_session(key, model, [lookup])

    assert {:ok, "It is 42."} = Condukt.Session.resume(pid)
    refute_received :looked_up
    assert_received {LLMProvider, :request, ^model_id, _, _}
    assert [^prompt, %Message{role: :assistant}] = Condukt.history(pid)
  end

  # A result can be missing before a later step, when its write failed, and
  # results are stored in the order they finish. Replay must still give every
  # call its result, in the order the model asked for them.
  test "replays each round closed and in call order", %{key: key} do
    prompt = Message.user("go")
    parallel = Message.assistant([{:tool_call, "c_slow", "slow", %{}}, {:tool_call, "c_fast", "fast", %{}}])
    lost = Message.assistant([{:tool_call, "c_lost", "lost", %{}}])
    answer = Message.assistant("Done.")
    slow = Message.tool_result("c_slow", "slow result")
    fast = Message.tool_result("c_fast", "fast result")

    :ok =
      Memory.append_journal(
        [
          {:run_start, 1, %{message: prompt}},
          {:assistant, 1, parallel},
          {:tool_intent, 1, %{call_id: "c_slow", replay_safe: false}},
          {:tool_intent, 1, %{call_id: "c_fast", replay_safe: false}},
          {:tool_result, 1, fast},
          {:tool_result, 1, slow},
          {:assistant, 1, lost},
          {:tool_intent, 1, %{call_id: "c_lost", replay_safe: false}},
          {:assistant, 1, answer}
        ],
        key: key
      )

    {model, _} = LLMProvider.model([])
    {:ok, pid} = start_session(key, model, [])

    assert {:ok, "Done."} = Condukt.Session.resume(pid)

    assert [
             ^prompt,
             ^parallel,
             ^slow,
             ^fast,
             ^lost,
             %Message{role: :tool_result, tool_call_id: "c_lost", content: {:error, "lost was interrupted" <> _}},
             ^answer
           ] = Condukt.history(pid)
  end

  test "giving up a run the model never answered keeps its prompt", %{key: key} do
    prompt = Message.user("unanswered")
    :ok = Memory.append_journal([{:run_start, 1, %{message: prompt}}], key: key)

    {model, _} = LLMProvider.model([LLMProvider.text_response("hello")])
    {:ok, pid} = start_session(key, model, [])

    assert {:ok, "hello"} = Condukt.run(pid, "something else")
    assert [^prompt, %Message{content: "something else"}, %Message{role: :assistant}] = Condukt.history(pid)
  end

  # A resume that reran a call and then failed keeps that call's real result,
  # rather than labelling it interrupted.
  test "a failed resume keeps the results it produced", %{key: key} do
    lookup =
      Condukt.tool(
        name: "lookup",
        description: "looks something up",
        parameters: %{type: "object", properties: %{}},
        replay_safe: true,
        call: fn _args, _context -> {:ok, "42"} end
      )

    prompt = Message.user("look it up")

    :ok =
      Memory.append_journal(
        [
          {:run_start, 1, %{message: prompt}},
          {:assistant, 1, Message.assistant([{:tool_call, "call_1", "lookup", %{}}])},
          {:tool_intent, 1, %{call_id: "call_1", replay_safe: true}}
        ],
        key: key
      )

    # No scripted response: the request after the tool round fails.
    {model, _} = LLMProvider.model([])
    {:ok, pid} = start_session(key, model, [lookup], retry: false)

    assert {:error, _reason} = Condukt.Session.resume(pid)
    assert [^prompt, _assistant, %Message{role: :tool_result, content: "42"}] = Condukt.history(pid)
  end

  test "an aborted run leaves nothing to resume", %{key: key} do
    test_pid = self()

    tool =
      Condukt.tool(
        name: "wait",
        description: "waits",
        parameters: %{type: "object", properties: %{}},
        call: fn _args, _context ->
          send(test_pid, {:waiting, self()})

          receive do
            :release -> {:ok, "done"}
          end
        end
      )

    {model, _} = LLMProvider.model([tool_call_response("call_1", "wait")])
    {:ok, pid} = start_session(key, model, [tool])

    run = Task.async(fn -> Condukt.run(pid, "wait", request_id: "aborted") end)
    assert_receive {:waiting, tool_pid}
    assert :ok = Condukt.abort(pid)
    assert Task.await(run) == {:error, :aborted}
    send(tool_pid, :release)

    assert Memory.load_journal(key: key) == {:ok, []}
    GenServer.stop(pid)

    {:ok, pid} = start_session(key, model, [tool])
    assert Condukt.Session.interrupted(pid) == nil
    assert Condukt.run(pid, "wait", request_id: "aborted") == {:error, :aborted}
  end

  @tag :tmp_dir
  test "resumes from the disk store", %{tmp_dir: tmp_dir} do
    test_pid = self()

    tool =
      Condukt.tool(
        name: "deploy",
        description: "deploys",
        parameters: %{type: "object", properties: %{}},
        call: fn _args, context ->
          send(test_pid, :deployed)
          Process.exit(context.agent, :kill)
          {:ok, "deployed"}
        end
      )

    disk = [session_store: Condukt.SessionStore.Disk, cwd: tmp_dir, id: "disk-session"]
    {model, _} = LLMProvider.model([tool_call_response("call_1", "deploy")])
    {:ok, pid} = start_session(nil, model, [tool], disk)
    assert {:error, {:session_exit, :killed}} = Condukt.run(pid, "deploy")
    assert_received :deployed

    {model, _} = LLMProvider.model([LLMProvider.text_response("Unsure whether it deployed.")])
    {:ok, pid} = start_session(nil, model, [tool], disk)

    assert {:ok, "Unsure whether it deployed."} = Condukt.Session.resume(pid)
    refute_received :deployed
    assert [_, _, %Message{content: {:error, _}}, _] = Condukt.history(pid)
    settle(pid)
    refute File.exists?(Path.join([tmp_dir, ".condukt", "sessions", "disk-session.store.journal"]))
  end

  # A new owner takes the session over at a higher epoch, reads what the old
  # one journaled, and settles the tool call it cannot know the outcome of.
  # A host runs one session per run, all at its lease epoch, and starts each
  # through the sessions supervisor, which is where the store's reads run.
  # Each session has to see what the one before it stored.
  test "consecutive sessions at one epoch on the object store each see the history before them" do
    {:ok, bucket} = ObjectStore.Memory.start_link()
    store = {ObjectStore, bucket: {ObjectStore.Memory, bucket}, key: "one-epoch", epoch: 3}

    for {prompt, answer} <- [{"first", "first answer"}, {"second", "second answer"}] do
      {model, _} = LLMProvider.model([LLMProvider.text_response(answer)])
      {:ok, pid} = Condukt.Sessions.start(DurableAgent, model: model, tools: [], session_store: store)
      assert {:ok, ^answer} = Condukt.run(pid, prompt)
      settle(pid)
      GenServer.stop(pid)
    end

    assert {:ok, %{messages: messages}} = elem(store, 1) |> Keyword.delete(:epoch) |> ObjectStore.load()
    assert Enum.map(messages, & &1.content) == ["first", [text: "first answer"], "second", [text: "second answer"]]
  end

  test "does not start on a snapshot from a newer version" do
    key = {:newer, make_ref()}
    :ok = Memory.save(%{Snapshot.new(%{messages: [Message.user("kept")]}) | version: 999}, key: key)
    {model, _} = LLMProvider.model([])

    assert {:error, {:snapshot_load_failed, {:unsupported_snapshot_version, 999}}} =
             start_session(key, model, [], session_store: Memory)
  end

  test "resumes from the object store at a new epoch" do
    test_pid = self()
    {:ok, bucket} = ObjectStore.Memory.start_link()

    store = fn epoch ->
      {ObjectStore, bucket: {ObjectStore.Memory, bucket}, key: "object-session", epoch: epoch}
    end

    tool =
      Condukt.tool(
        name: "deploy",
        description: "deploys",
        parameters: %{type: "object", properties: %{}},
        call: fn _args, context ->
          send(test_pid, :deployed)
          Process.exit(context.agent, :kill)
          {:ok, "deployed"}
        end
      )

    {model, _} = LLMProvider.model([tool_call_response("call_1", "deploy")])
    {:ok, pid} = start_session(nil, model, [tool], session_store: store.(1))
    assert {:error, {:session_exit, :killed}} = Condukt.run(pid, "deploy")
    assert_received :deployed

    {model, _} = LLMProvider.model([LLMProvider.text_response("Unsure whether it deployed.")])
    {:ok, pid} = start_session(nil, model, [tool], session_store: store.(2))

    assert {:ok, "Unsure whether it deployed."} = Condukt.Session.resume(pid)
    refute_received :deployed
    assert [_, _, %Message{content: {:error, _}}, _] = Condukt.history(pid)
    settle(pid)

    assert ObjectStore.load_journal(elem(store.(2), 1)) == {:ok, []}
    assert ObjectStore.append_journal([{:resume, 1, nil}], elem(store.(1), 1)) == {:error, :fenced}
  end

  # The outcomes live in the snapshot, so request ids need a store but not a
  # journal.
  test "a store without a journal still runs a request id once", %{key: key} do
    {model, model_id} = LLMProvider.model([LLMProvider.text_response("ok")])

    {:ok, pid} =
      DurableAgent.start_link(
        model: model,
        session_store: {SnapshotOnlyStore, test_pid: self()},
        session_store_key: key,
        load_project_instructions: false
      )

    assert {:ok, "ok"} = Condukt.run(pid, "go", request_id: "r")
    assert_receive {LLMProvider, :request, ^model_id, _, _}
    assert {:ok, "ok"} = Condukt.run(pid, "go", request_id: "r")
    assert Condukt.Session.interrupted(pid) == nil
    assert Condukt.Session.resume(pid) == {:error, :nothing_to_resume}

    assert_received {:saved_snapshot, snapshot}
    assert {_last_run_id, [{"r", {:ok, "ok"}}]} = Snapshot.runs(snapshot)
  end

  describe "a submitted input" do
    setup do
      inbox_name = :"durable_inbox_#{System.unique_integer([:positive])}"
      start_supervised!({Inbox.Memory, name: inbox_name})

      %{
        id: "durable-#{System.unique_integer([:positive])}",
        inbox: {Inbox.Memory, name: inbox_name},
        sender: "sender-#{System.unique_integer([:positive])}"
      }
    end

    test "is settled by the run a restart resumes", %{key: key, id: id, inbox: inbox, sender: sender} do
      # A queued input streams; the session dies while the response is held.
      {model, model_id} = LLMProvider.model([LLMProvider.stream_response([{:text, "Let me "}, :hold])])
      {:ok, pid} = start_supervised_session(id, key, model, inbox: inbox)

      assert Condukt.Sessions.submit(id, "question", request_id: "req-1", from: sender, report: true, inbox: inbox) ==
               :ok

      assert_receive {LLMProvider, :stream_request, ^model_id, _context, _opts}, 1_000
      kill(pid)

      {model, _} = LLMProvider.model([LLMProvider.text_response("answer")])
      {:ok, pid} = start_supervised_session(id, key, model, inbox: inbox)
      assert %{request_id: "req-1"} = Condukt.Session.interrupted(pid)

      assert {:ok, "answer"} = Condukt.Session.resume(pid)
      assert await_reports(inbox, sender, 1) == ["[session #{id} answered] answer"]
    end

    test "waits for the resume of a run whose worker exited", %{key: key, id: id, inbox: inbox, sender: sender} do
      crash =
        Condukt.tool(
          name: "crash",
          description: "exits",
          parameters: %{type: "object", properties: %{}},
          call: fn _args, context -> exit_worker(context, :boom) end
        )

      {model, _} =
        LLMProvider.model([
          LLMProvider.stream_response([{:tool_call, "call_1", "crash", %{}}]),
          LLMProvider.text_response("It crashed.")
        ])

      {:ok, pid} = start_supervised_session(id, key, model, inbox: inbox, tools: [crash])
      assert Condukt.Sessions.submit(id, "crash it", request_id: "c", from: sender, report: true, inbox: inbox) == :ok
      assert %{request_id: "c"} = await(fn -> Condukt.Session.interrupted(pid) end)

      # The run is not over: the sender hears how it ends, once.
      assert {:ok, "It crashed."} = Condukt.Session.resume(pid)
      assert await_reports(inbox, sender, 1) == ["[session #{id} answered] It crashed."]
    end

    test "that cannot resume its run is settled, and the next input starts", %{
      key: key,
      id: id,
      inbox: inbox,
      sender: sender
    } do
      :ok = Memory.append_journal([{:run_start, 1, %{message: Message.user("one"), request_id: "r1"}}], key: key)

      # Both wait in the inbox, so the session takes them together as it starts.
      assert Condukt.Sessions.submit(id, "one", request_id: "r1", from: sender, report: true, inbox: inbox) == :ok
      assert Condukt.Sessions.submit(id, "two", request_id: "r2", inbox: inbox) == :ok

      {model, _} = LLMProvider.model([LLMProvider.stream_response([{:text, "second"}])])
      {:ok, pid} = start_supervised_session(id, key, model, inbox: inbox, restart_limit: 0)

      assert await_reports(inbox, sender, 1) == ["[session #{id} failed: {:restart_limit, 0}]"]

      assert await(fn -> match?([_, _, %Message{role: :assistant}], Condukt.history(pid)) end)
      assert [%Message{content: "one"}, %Message{content: "two"}, %Message{role: :assistant}] = Condukt.history(pid)
    end

    test "reports image preflight rejection to a redelivered input without settling the original", %{
      key: key,
      id: id,
      inbox: inbox,
      sender: sender
    } do
      original_sender = "original-#{sender}"

      {:ok, original} = Input.new(id, "old image", request_id: "r1", from: original_sender, report: true)

      records = [
        {:run_start, 1, %{message: Message.user("old image", [Images.attachment()]), request_id: "r1", input: original}}
      ]

      :ok = Memory.append_journal(records, key: key)
      {model, model_id} = LLMProvider.model([])
      {:ok, pid} = start_supervised_session(id, key, model, inbox: inbox, image_policy: Images.policy(self()))
      interrupted = Condukt.Session.interrupted(pid)

      assert {:error, :image_history_requires_repair} = Condukt.Session.resume(pid)
      assert [{:error, :image_history_requires_repair}] = Condukt.Session.resume_stream(pid) |> Enum.to_list()

      assert :ok =
               Condukt.Sessions.submit(id, "redelivered", request_id: "r1", from: sender, report: true, inbox: inbox)

      assert await_reports(inbox, sender, 1) == ["[session #{id} failed: :image_history_requires_repair]"]
      assert await_reports(inbox, original_sender, 0) == []
      assert Condukt.Session.interrupted(pid) == interrupted
      assert {:ok, ^records} = Memory.load_journal(key: key)
      refute_receive {LLMProvider, :request, ^model_id, _, _}, 20
      refute_receive {LLMProvider, :stream_request, ^model_id, _, _}, 20
    end

    test "redelivered after its run was aborted settles as aborted", %{key: key, id: id, inbox: inbox, sender: sender} do
      :ok =
        Memory.append_journal(
          [{:run_start, 1, %{message: Message.user("one"), request_id: "r1"}}, {:run_end, 1, {:error, :aborted}}],
          key: key
        )

      {model, _} = LLMProvider.model([LLMProvider.stream_response([{:text, "ok"}])])
      {:ok, _pid} = start_supervised_session(id, key, model, inbox: inbox)

      # An aborted input sends no report. The second input's report comes after
      # the first input was settled.
      assert Condukt.Sessions.submit(id, "one", request_id: "r1", from: sender, report: true, inbox: inbox) == :ok
      assert Condukt.Sessions.submit(id, "two", request_id: "r2", from: sender, report: true, inbox: inbox) == :ok
      assert await_reports(inbox, sender, 1) == ["[session #{id} answered] ok"]
      assert await_reports(inbox, sender, 0) == []
    end
  end

  # The journal of an interrupted run follows the history it started from, so
  # compacting that history would make the next restart drop the run.
  test "refuses to compact while a run is interrupted", %{key: key} do
    :ok = Memory.append_journal([{:run_start, 1, %{message: Message.user("one"), request_id: "r1"}}], key: key)

    {model, _} = LLMProvider.model([])
    opts = [compactor: {Condukt.Compactor.Sliding, keep: 0}]
    {:ok, pid} = start_session(key, model, [], opts)
    assert Condukt.Session.compact(pid) == {:error, :interrupted}
    kill(pid)

    {:ok, pid} = start_session(key, model, [], opts)
    assert %{request_id: "r1"} = Condukt.Session.interrupted(pid)
  end

  # Unlinked, so a test can kill the session, and stopped when the test ends.
  defp exit_worker(context, reason) do
    Process.exit(:sys.get_state(context.agent).turn.worker, reason)
    receive do: (:never -> {:ok, "unreachable"})
  end

  defp start_session(key, model, tools, opts \\ []) do
    with {:ok, pid} = started <- start_unlinked_session(key, model, tools, opts) do
      on_exit(fn -> Process.exit(pid, :kill) end)
      started
    end
  end

  defp start_unlinked_session(key, model, tools, opts) do
    Condukt.Session.start(
      DurableAgent,
      Keyword.merge(
        [
          model: model,
          tools: tools,
          session_store: Memory,
          session_store_key: key,
          load_project_instructions: false
        ],
        opts
      )
    )
  end

  defp start_supervised_session(id, key, model, opts \\ []) do
    Condukt.Sessions.start(
      DurableAgent,
      [
        id: id,
        model: model,
        tools: [],
        session_store: Memory,
        session_store_key: key,
        load_project_instructions: false
      ]
      |> Keyword.merge(opts)
    )
  end

  # Streams a prompt until the first event `stop?` accepts, and returns it.
  # Stops reading there, so a session killed afterwards does not leave the
  # test waiting for the rest of the stream.
  defp stream_until(pid, prompt, opts, stop?) do
    pid
    |> Condukt.stream(prompt, opts)
    |> Enum.find(fn event ->
      refute match?({:error, _}, event), "stream failed: #{inspect(event)}"
      stop?.(event)
    end)
  end

  defp kill(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
  end

  # A stream's subscriber gets `:done` before the session saves the snapshot
  # and clears the journal in the same callback; this waits for that callback.
  defp settle(pid), do: _ = :sys.get_state(pid)

  defp tool_call_response(id, name), do: tool_call_response([{id, name}])

  defp tool_call_response(calls) do
    calls = Enum.map(calls, fn {id, name} -> ToolCall.new(id, name, JSON.encode!(%{})) end)
    LLMProvider.response(%ReqLLM.Message{role: :assistant, content: [], tool_calls: calls}, :tool_calls)
  end

  # Takes the reports the sender's inbox got, waiting until there are `count`.
  defp await_reports(inbox, sender, count, taken \\ [], attempts \\ 200) do
    {:ok, inputs} = Inbox.take(inbox, sender)
    taken = taken ++ Enum.map(inputs, & &1.text)

    if length(taken) < count and attempts > 0 do
      receive do
      after
        5 -> await_reports(inbox, sender, count, taken, attempts - 1)
      end
    else
      taken
    end
  end

  defp await(fun, attempts \\ 200) do
    case fun.() do
      falsy when falsy in [nil, false] and attempts > 0 ->
        receive do
        after
          5 -> await(fun, attempts - 1)
        end

      result ->
        result
    end
  end

  # Called from inside a tool, to crash only once another record is stored.
  defp await_journal(key, match?, attempts \\ 500) do
    {:ok, records} = Memory.load_journal(key: key)

    if attempts > 0 and not Enum.any?(records, match?) do
      receive do
      after
        5 -> await_journal(key, match?, attempts - 1)
      end
    end
  end
end
