defmodule Tuist.MCP.Components.Tools.SandboxTools do
  @moduledoc false
  alias Tuist.FeatureFlags
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Sandboxes.Query

  # The same rule as the HTTP API (`TuistWeb.API.SandboxesController`):
  # members (`:sandboxes_write`) use every sandbox in the account.
  def execute(action, conn, args) do
    with {:ok, account} <- MCPTool.resolve_and_authorize_account(args, conn.assigns, :write, :sandboxes),
         {:enabled, true} <- {:enabled, FeatureFlags.sandboxes_enabled?(account)} do
      case Query.run(action, account, args) do
        {:ok, data} -> {:ok, data}
        {:error, reason} -> {:error, reason |> Query.error() |> elem(1)}
      end
    else
      {:enabled, false} -> {:error, "Agent sandboxes are not enabled for this account."}
      {:error, _message} = error -> error
    end
  end
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
  def description, do: "Get a sandbox's status, shape, node, archive and timestamps. Requires an account member."

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
      "Get an account's sandbox vCPU-hours, sandboxes created, session, setup and time-to-start durations, and peak vCPUs and memory against its limits for a time range, with trends against the previous range. Defaults to the last 30 days; maximum range is 90 days. Requires an account member."

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
    Boot a Linux or macOS sandbox from a template, or a macOS one from its repository's ready snapshot, and return it once it runs. Linux sandboxes take 2x4096, 4x8192 or 8x16384 vCPUs x memory MB (default 2x4096); macOS sandboxes take 8x8192, 8x16384 or 8x24576 (default 8x8192). It counts toward the account's sandbox limits. Requires an account member.

    #{xcode_guidance()}

    To build, test or run local Apple-platform code (xcodebuild, the iOS Simulator) from a machine that is not a Mac, create one macOS sandbox per task, reuse it, and drive it with the Tuist CLI where the code is. These tools cannot reach local files. If `tuist` is missing or `tuist sandbox --help` doesn't list `sync`, install the newest CLI: download `tuist-linux-x86_64.tar.gz` (or `-aarch64`) from the newest https://github.com/tuist/tuist release whose tag is a bare version such as 4.216.3 (other tags belong to other components), and put the `tuist` it contains on PATH. The CLI needs its own authentication, `TUIST_TOKEN` or `tuist auth login`; this server's sign-in does not carry over. Pass `--account <account_handle>` to every command.
    - For a macOS sandbox, pass `repository` with the GitHub `owner/name` of the repository you work in (from `git remote get-url origin`). When the account prepares Macs for it, the sandbox boots with the default branch cloned to `$HOME/work/<name>`, set up and built, and the first sync sends only what differs; otherwise it boots bare.
    - Before every command, run `tuist sandbox sync <id> --json`. It mirrors the files Git does not ignore, committed or not, and returns the repository's `root` on the Mac. It is one-way: edit files locally, not on the Mac.
    - The Mac has no Tuist CLI unless it booted ready. After the first sync, run `mise install` in `root` to install the repository's pinned Tuist (fast when it is installed already). Every command already has `$HOME/.local/share/mise/shims` on `PATH`, so `tuist` and other mise tools work in commands and in Xcode build phases. Each command gets `TUIST_URL`, the in-rack `TUIST_CACHE_ENDPOINT` and a short-lived `TUIST_OIDC_TOKEN`, so Tuist 4.218.0 or later uses the account's cache without credentials from you; with 4.215.0 to 4.217.x, run `tuist auth login` first in the same command.
    - Run commands with `tuist sandbox exec <id> --cwd <root> -- '<command>'`. It streams output, waits while the Mac's host is busy, and exits with the command's status; stopping it cancels the command. Start long builds in the background with output in a log file.
    - Copy results such as screenshots, an .xcresult bundle or a built app back with `tuist sandbox cp <id>:<path> <local-path>`.
    - Keep the default shape unless a build runs out of memory, and run only the builds and tests the user asked for: every larger shape and every extra scheme makes the user wait longer.
    - Delete the sandbox when the task is done.
    """

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:create, conn, args)

  # The served Xcodes are this server's, so the agent sees what it can pick.
  defp xcode_guidance do
    case Tuist.Sandboxes.Xcode.versions() do
      [] ->
        "macOS sandboxes boot one Xcode; `xcode_version` is not available on this server."

      [default | _] = versions ->
        "For a macOS sandbox, first find the Xcode the repository builds with, and pass it as `xcode_version`. Each repository records it differently, so look before you create: `.xcode-version`, `.tool-versions` or `mise.toml`, the Xcode its CI selects (`xcode-version:`, `DEVELOPER_DIR`, `xcode-select`, a runner image or label naming Xcode), its Tuist runner profile, or its README or contributor docs. Use the most specific version it names; when the user asks for another Xcode, use theirs and tell them the build will not be cached. A different Xcode, even a different patch release, misses the repository's binary and compilation caches and its ready snapshot, so the whole project builds from source. It implies `platform: darwin`. Served: #{Enum.join(versions, ", ")}. Only when the repository names no Xcode, omit it and the sandbox boots #{default}. A version not served is refused; then pick the nearest served one and tell the user which you used and why. A sandbox keeps its Xcode; another one needs a new sandbox."
    end
  end
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
      "Pause a running sandbox: its VM is snapshotted to its node's disk and stops using vCPUs and memory. Refused while a worker or command runs. Requires an account member."

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
      "Resume a paused or archived sandbox. An archived one is restored from object storage first. Requires an account member."

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
      "Queue moving a paused sandbox's disks to object storage, freeing them on its node. It stays paused until the upload completes, then becomes archived; resuming restores it. Requires an account member."

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
    do: "Delete a sandbox and its disks after user confirmation. This cannot be undone. Requires an account member."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:delete, conn, args)
end
