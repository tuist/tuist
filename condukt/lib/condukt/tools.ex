defmodule Condukt.Tools do
  @moduledoc """
  Built-in tools for Condukt.

  ## Default Tool Sets

  - `coding_tools/0` - Read, Bash, Edit, Write, Glob, Grep (default for coding agents)
  - `read_only_tools/0` - Read, Bash, Glob, Grep (read-only access)

  ## Individual Tools

  - `Condukt.Tools.Read` - Read file contents
  - `Condukt.Tools.Bash` - Execute bash commands
  - `Condukt.Tools.Command` - Execute one trusted command without shell parsing
  - `Condukt.Tools.Edit` - Surgical file edits
  - `Condukt.Tools.Write` - Write files
  - `Condukt.Tools.Glob` - Find files by glob pattern
  - `Condukt.Tools.Grep` - Search file contents by regex
  - `Condukt.Tools.Subagent` - Delegate work to registered sub-agent roles

  Every built-in tool routes its filesystem and process work through the
  active `Condukt.Sandbox`, so the same tool list works against the host
  filesystem (`Sandbox.Local`), an isolated virtual filesystem
  (`Sandbox.Virtual`), or a microVM-backed guest (`Sandbox.Microsandbox`).
  Command tools also receive session secrets as environment variables when
  configured at `start_link/1`.

  ## Usage

      defmodule MyAgent do
        use Condukt

        @impl true
        def tools do
          Condukt.Tools.coding_tools()
        end
      end

  Or pick specific tools:

      def tools do
        [
          Condukt.Tools.Read,
          Condukt.Tools.Bash
        ]
      end
  """

  alias Condukt.Tools.{Bash, Edit, Glob, Grep, Read, Write}

  @doc """
  Returns the default coding tools: Read, Bash, Edit, Write, Glob, Grep.

  These tools provide full filesystem access for coding agents through the
  active sandbox.
  """
  def coding_tools do
    [Read, Bash, Edit, Write, Glob, Grep]
  end

  @doc """
  Returns read-only tools: Read, Bash, Glob, Grep.

  Use these when you want the agent to explore but not modify files.
  Note that Bash can still execute arbitrary commands. Prefer a parameterized
  `Condukt.Tools.Command` when you want to grant a specific executable such as
  `git`, `gh`, or `mix`.
  """
  def read_only_tools do
    [Read, Bash, Glob, Grep]
  end

  @doc """
  Returns all built-in tools that can be attached directly to an agent.

  `Condukt.Tools.Subagent` is injected automatically when an agent declares
  sub-agents, so it is not included here.
  """
  def all do
    [Read, Bash, Edit, Write, Glob, Grep]
  end
end
