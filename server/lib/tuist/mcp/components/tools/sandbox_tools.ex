defmodule Tuist.MCP.Components.Tools.SandboxTools do
  @moduledoc false
  alias Tuist.FeatureFlags
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Query

  # The same rule as the HTTP API (`TuistWeb.API.SandboxesController`):
  # members (`:sandboxes_use`) list, create, pause, resume and delete
  # sandboxes, but only those `Sandboxes.member_sandbox?/1` allows; analytics
  # and archiving stay with account administrators.
  @admin_actions [:analytics, :archive]

  def execute(action, conn, args) do
    with {:ok, account} <- authorize_account(action, args, conn.assigns),
         {:enabled, true} <- {:enabled, FeatureFlags.sandboxes_enabled?(account)},
         :ok <- authorize_sandbox(account, args, conn.assigns) do
      case Query.run(action, account, args) do
        {:ok, data} -> {:ok, data}
        {:error, reason} -> {:error, reason |> Query.error() |> elem(1)}
      end
    else
      {:enabled, false} -> {:error, "Agent sandboxes are not enabled for this account."}
      {:error, _message} = error -> error
    end
  end

  defp authorize_account(action, args, assigns) when action in @admin_actions,
    do: MCPTool.resolve_and_authorize_account(args, assigns, :update, :account)

  defp authorize_account(_action, args, assigns),
    do: MCPTool.resolve_and_authorize_account(args, assigns, :use, :sandboxes)

  defp authorize_sandbox(account, %{"sandbox_id" => sandbox_id}, assigns) do
    with {:error, _admin_only} <- MCPTool.authorize_account(assigns, account, :update, :account),
         {:ok, sandbox} <- Sandboxes.get_sandbox(account, sandbox_id),
         false <- Sandboxes.member_sandbox?(sandbox) do
      {:error, "Only account administrators can use sandboxes that serve agents, Amp or remote execution."}
    else
      _ -> :ok
    end
  end

  defp authorize_sandbox(_account, _args, _assigns), do: :ok
end

defmodule Tuist.MCP.Components.Tools.ListSandboxes do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "list_sandboxes",
    title: "List Sandboxes",
    read_only_hint: true,
    destructive_hint: false,
    schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.inputs(:list)),
    output_schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.response(:list))

  @impl EMCP.Tool
  def description,
    do:
      "List an account's sandboxes, newest first by default, with their status, shape and timestamps. Filter by status, vCPUs or text in the sandbox, Amp Orb or Anthropic session ID. Requires an account member."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:list, conn, args)
end

defmodule Tuist.MCP.Components.Tools.GetSandbox do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "get_sandbox",
    title: "Get Sandbox",
    read_only_hint: true,
    destructive_hint: false,
    schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.inputs(:show)),
    output_schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.sandbox())

  @impl EMCP.Tool
  def description,
    do:
      "Get a sandbox's status, shape, node, archive and timestamps. Requires an account member; sandboxes that serve agents, Amp or remote execution require account administration."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:show, conn, args)
end

defmodule Tuist.MCP.Components.Tools.GetSandboxAnalytics do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "get_sandbox_analytics",
    title: "Get Sandbox Analytics",
    read_only_hint: true,
    destructive_hint: false,
    schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.inputs(:analytics)),
    output_schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.response(:analytics))

  @impl EMCP.Tool
  def description,
    do:
      "Get an account's sandbox vCPU-hours, sandboxes created, session, setup and time-to-start durations, and peak vCPUs, memory and disk against its limits for a time range, with trends against the previous range. Defaults to the last 30 days; maximum range is 90 days. Requires account administration."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:analytics, conn, args)
end

defmodule Tuist.MCP.Components.Tools.CreateSandbox do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "create_sandbox",
    title: "Create Sandbox",
    read_only_hint: false,
    destructive_hint: false,
    schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.inputs(:create)),
    output_schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.sandbox())

  @impl EMCP.Tool
  def description,
    do: """
    Boot a bare Linux or macOS sandbox from a template and return it once it runs. Linux sandboxes take 2x4096, 4x8192 or 8x16384 vCPUs x memory MB (default 2x4096); macOS sandboxes take 8x8192, 8x16384 or 8x24576 (default 8x8192). It counts toward the account's sandbox limits. Requires an account member.

    To build, test or run local Apple-platform code (xcodebuild, the iOS Simulator) from a machine that is not a Mac, create one macOS sandbox per task, reuse it, and drive it with the Tuist CLI where the code is. These tools cannot reach local files. If `tuist` is missing or `tuist sandbox --help` doesn't list `sync`, install the newest CLI: download `tuist-linux-x86_64.tar.gz` (or `-aarch64`) from the newest https://github.com/tuist/tuist release whose tag is a bare version such as 4.216.3 (other tags belong to other components), and put the `tuist` it contains on PATH. The CLI needs its own authentication, `TUIST_TOKEN` or `tuist auth login`; this server's sign-in does not carry over. Pass `--account <account_handle>` to every command.
    - Before every command, run `tuist sandbox sync <id> --json`. It mirrors the files Git does not ignore, committed or not, and returns the repository's `root` on the Mac. It is one-way: edit files locally, not on the Mac.
    - Run commands with `tuist sandbox exec <id> --cwd <root> -- '<command>'`. It streams output, waits while the Mac's host is busy, and exits with the command's status; stopping it cancels the command. Start long builds in the background with output in a log file.
    - Copy results such as screenshots, an .xcresult bundle or a built app back with `tuist sandbox cp <id>:<path> <local-path>`.
    - Delete the sandbox when the task is done.
    """

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:create, conn, args)
end

defmodule Tuist.MCP.Components.Tools.PauseSandbox do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "pause_sandbox",
    title: "Pause Sandbox",
    read_only_hint: false,
    destructive_hint: false,
    schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.inputs(:pause)),
    output_schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.sandbox())

  @impl EMCP.Tool
  def description,
    do:
      "Pause a running sandbox: its VM is snapshotted to its node's disk and stops using vCPUs and memory. Refused while a worker or command runs. Requires an account member; sandboxes that serve agents, Amp or remote execution require account administration."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:pause, conn, args)
end

defmodule Tuist.MCP.Components.Tools.ResumeSandbox do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "resume_sandbox",
    title: "Resume Sandbox",
    read_only_hint: false,
    destructive_hint: false,
    schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.inputs(:resume)),
    output_schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.sandbox())

  @impl EMCP.Tool
  def description,
    do:
      "Resume a paused or archived sandbox. An archived one is restored from object storage first. Requires an account member; sandboxes that serve agents, Amp or remote execution require account administration."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:resume, conn, args)
end

defmodule Tuist.MCP.Components.Tools.ArchiveSandbox do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "archive_sandbox",
    title: "Archive Sandbox",
    read_only_hint: false,
    destructive_hint: false,
    schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.inputs(:archive)),
    output_schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.sandbox())

  @impl EMCP.Tool
  def description,
    do:
      "Queue moving a paused sandbox's disks to object storage, freeing them on its node. It stays paused until the upload completes, then becomes archived; resuming restores it. Requires account administration."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:archive, conn, args)
end

defmodule Tuist.MCP.Components.Tools.DeleteSandbox do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "delete_sandbox",
    title: "Delete Sandbox",
    read_only_hint: false,
    destructive_hint: true,
    schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.inputs(:delete)),
    output_schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.response(:delete))

  @impl EMCP.Tool
  def description,
    do:
      "Delete a sandbox and its disks after user confirmation. This cannot be undone. Requires an account member; sandboxes that serve agents, Amp or remote execution require account administration."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:delete, conn, args)
end
