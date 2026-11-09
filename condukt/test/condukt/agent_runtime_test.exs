defmodule Condukt.AgentRuntimeTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Condukt.Message

  @moduletag :tmp_dir

  setup :set_mimic_from_context
  setup :verify_on_exit!

  defmodule EchoRuntime do
    @behaviour Condukt.AgentRuntime

    @impl true
    def run(prompt, context, opts) do
      send(context.user_state.test_pid, {:runtime_called, prompt, context, opts})
      {:ok, %{response: "runtime: #{prompt}", assigns: Map.put(context.assigns, :runtime, :called)}}
    end
  end

  defmodule MissingCallbackRuntime do
    @moduledoc false
  end

  defmodule RuntimeAgent do
    use Condukt.Agent, runtime: {EchoRuntime, default: true}

    @impl true
    def system_prompt, do: "Use the external coding runtime."

    @impl true
    def init(opts) do
      {:ok, %{test_pid: Keyword.fetch!(opts, :test_pid)}}
    end
  end

  defmodule InvalidRuntimeAgent do
    use Condukt.Agent, runtime: MissingCallbackRuntime
  end

  defmodule CodexAgent do
    use Condukt.Agent,
      runtime: {Condukt.AgentRuntimes.Codex, command: "codex-test", sandbox: "read-only"}

    @impl true
    def system_prompt, do: "Return terse answers."
  end

  defmodule ClaudeAgent do
    use Condukt.Agent,
      runtime: {Condukt.AgentRuntimes.Claude, command: "claude-test", permission_mode: "dontAsk"}

    @impl true
    def system_prompt, do: "Return terse answers."
  end

  test "Condukt.Agent accepts a runtime option" do
    assert RuntimeAgent.runtime() == {EchoRuntime, default: true}
    assert RuntimeAgent.system_prompt() == "Use the external coding runtime."
  end

  test "module-defined one-shot runs delegate to the configured runtime" do
    assert {:ok, "runtime: implement this"} =
             Condukt.run(RuntimeAgent, "implement this",
               test_pid: self(),
               load_project_instructions: false,
               max_turns: 1
             )

    assert_receive {:runtime_called, "implement this", context, opts}

    assert context.agent_module == RuntimeAgent
    assert context.system_prompt == "Use the external coding runtime."
    assert context.runtime_opts == [default: true]
    assert context.assigns == %{}
    assert Keyword.fetch!(opts, :max_turns) == 1
  end

  test "persistent runtime-backed sessions persist normalized history" do
    {:ok, agent} = RuntimeAgent.start_link(test_pid: self(), load_project_instructions: false)

    assert {:ok, "runtime: write code"} = Condukt.run(agent, "write code")

    assert [
             %Message{role: :user, content: "write code"},
             %Message{role: :assistant, content: "runtime: write code"}
           ] = Condukt.history(agent)

    GenServer.stop(agent)
  end

  test "runtime modules must implement run/3" do
    previous = Process.flag(:trap_exit, true)

    try do
      assert {:error, {:runtime_init_failed, {:runtime_missing_run_callback, MissingCallbackRuntime}}} =
               InvalidRuntimeAgent.start_link(load_project_instructions: false)
    after
      Process.flag(:trap_exit, previous)
    end
  end

  test "Codex runtime shells out through codex exec", %{tmp_dir: tmp_dir} do
    MuonTrap
    |> expect(:cmd, fn "bash", ["-lc", "exec \"$@\" < /dev/null", "condukt-agent-runtime", "codex-test" | args], opts ->
      assert opts[:cd] == tmp_dir
      assert opts[:stderr_to_stdout] == true
      assert opts[:parallelism] == false
      assert opts[:timeout] == 295_000
      assert {"TERM", "dumb"} in opts[:env]

      assert [
               "--sandbox",
               "read-only",
               "--ask-for-approval",
               "never",
               "exec",
               "--skip-git-repo-check",
               "--color",
               "never",
               "-C",
               ^tmp_dir,
               "-o",
               output_path,
               prompt
             ] = args

      File.write!(output_path, "codex result\n")
      assert prompt =~ "Return terse answers."
      assert prompt =~ "Task:\nList files"

      {"ignored stdout\n", 0}
    end)

    assert {:ok, "codex result"} =
             Condukt.run(CodexAgent, "List files", cwd: tmp_dir, load_project_instructions: false)
  end

  test "Claude runtime shells out through claude print", %{tmp_dir: tmp_dir} do
    MuonTrap
    |> expect(:cmd, fn "bash",
                       ["-lc", "exec \"$@\" < /dev/null", "condukt-agent-runtime", "claude-test" | args],
                       opts ->
      assert opts[:cd] == tmp_dir
      assert opts[:stderr_to_stdout] == true
      assert opts[:parallelism] == false
      assert {"TERM", "dumb"} in opts[:env]

      assert [
               "--print",
               "--output-format",
               "text",
               "--permission-mode",
               "dontAsk",
               "--no-session-persistence",
               "--system-prompt",
               "Return terse answers.",
               "List files"
             ] = args

      {"claude result\n", 0}
    end)

    assert {:ok, "claude result"} =
             Condukt.run(ClaudeAgent, "List files", cwd: tmp_dir, load_project_instructions: false)
  end
end
