defmodule Tuist.MCP.Components.Tools.SandboxTools do
  @moduledoc false
  alias Tuist.FeatureFlags
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Query

  # The device actions run fixed commands in the guest.
  @guest_actions [:devices, :boot_device, :launch_app, :open_url, :screenshot]

  # The same rule as the HTTP API (`TuistWeb.API.SandboxesController`):
  # members (`:sandboxes_write`) use every sandbox in the account, and only
  # admins reach inside one that serves an integration.
  def execute(action, conn, args) do
    with {:ok, account} <- MCPTool.resolve_and_authorize_account(args, conn.assigns, :write, :sandboxes),
         {:enabled, true} <- {:enabled, FeatureFlags.sandboxes_enabled?(account)},
         :ok <- guest_access(action, conn, account, args) do
      case Query.run(action, account, args) do
        {:ok, data} -> {:ok, data}
        {:error, reason} -> {:error, error_text(Query.error(reason))}
      end
    else
      {:enabled, false} -> {:error, "Agent sandboxes are not enabled for this account."}
      {:error, _message} = error -> error
    end
  end

  defp guest_access(action, conn, account, %{"sandbox_id" => id}) when action in @guest_actions do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, sandbox} <- Sandboxes.get_sandbox(account, id),
         false <- Sandboxes.member_sandbox?(sandbox),
         {:error, _} <- MCPTool.authorize_account(conn.assigns, account, :update, :account) do
      {:error, error_text(Query.error(:integration_sandbox))}
    else
      _ -> :ok
    end
  end

  defp guest_access(_action, _conn, _account, _args), do: :ok

  # The code leads the text, so an agent branches on it as it would on the
  # API's `code`; the message after it says what to do.
  defp error_text(%{code: code, message: message} = error) do
    retry = if seconds = error[:retry_after], do: "\nretry_after_seconds: #{seconds}", else: ""
    "code: #{code}\n#{message}#{retry}"
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
    - For a macOS sandbox, pass `repository` with the GitHub `owner/name` of the repository you work in (from `git remote get-url origin`). When the account prepares Macs for it, the sandbox boots with the default branch cloned to `$HOME/work/<name>`, set up and built, and the first sync sends only what differs; otherwise it boots bare. A prepared Mac also starts booting the Xcode's newest Pro iPhone simulator (iPhone 18 Pro on Xcode 27.2) in the background, ready about half a minute later: build and test on it (`-destination 'platform=iOS Simulator,name=iPhone 18 Pro'`) unless the user names another device, since a simulator you create or boot yourself starts cold.
    - Before every command, run `tuist sandbox sync <id> --json`. It mirrors the files Git does not ignore, committed or not, one way, and returns the repository's `root` on the Mac.
    - Run commands with `tuist sandbox exec <id> --cwd <root> --wait <seconds> -- '<command>'`, with `--wait` a minute under your tool-call time limit. It streams output, waits while the Mac's host is busy, and exits with the command's status; stopping it cancels the command. When `--wait` passes first, the command keeps running: it exits with 75 and prints the `tuist sandbox exec ... --attach` command that continues where the output stopped and ends with the command's status. Run builds and tests this way in the foreground; don't background them and poll a log.
    - The Mac has `tuist`, the repository's own version when it pins one through mise, signed in to the account's cache in every command. Once, read the Mac's guide with `tuist sandbox exec <id> -- cat /opt/tuist/agent-guide.md`: its Xcode and simulators, what a ready snapshot holds, and copying results back. A Mac without the guide predates it: run `mise install` in `root` there for Tuist.
    - To show the user an app running in the iOS Simulator, build it on the Mac with `tuist sandbox exec`, then use `list_sandbox_devices`, `boot_sandbox_device`, `launch_sandbox_app` (with `app_path`, the built .app) and `get_sandbox_screenshot`, which returns the image; `open_sandbox_url` opens a deep link. Where you have the CLI, `tuist sandbox screenshot <id> --out <file>.png` saves the full-size PNG instead (`--screen` for the whole screen, `--device` for one of several booted simulators).
    - Keep the default shape unless a build runs out of memory, and run only the builds and tests the user asked for: every larger shape and every extra scheme makes the user wait longer.
    - The sandbox runs until `expires_at`, two hours from creation unless you pass `lifetime_seconds` (at most a day). The limit is hard: then any running command is cancelled and the sandbox is paused and archived, keeping its files; a later command resumes it with a new lifetime. Before a long build or test run, check `expires_at` and call `extend_sandbox` so it outlasts the command's timeout. Delete the sandbox when the task is done.
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

defmodule Tuist.MCP.Components.Tools.ExtendSandbox do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "extend_sandbox",
    title: "Extend Sandbox",
    read_only_hint: false,
    destructive_hint: false,
    schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.inputs(:extend)),
    output_schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.sandbox())

  @impl EMCP.Tool
  def description,
    do:
      "Start a sandbox's lifetime again from now, with `lifetime_seconds` when given (at most 24 hours), so it keeps running past its `expires_at`. Call it before a command that may outlast `expires_at`: when a lifetime ends, running commands are cancelled and the sandbox is paused and archived, keeping its files; resuming one starts a new lifetime. Requires an account member."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:extend, conn, args)
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

defmodule Tuist.MCP.Components.Tools.ListSandboxDevices do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "list_sandbox_devices",
    title: "List Sandbox Devices",
    read_only_hint: true,
    destructive_hint: false,
    schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.inputs(:devices)),
    output_schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.response(:devices))

  @impl EMCP.Tool
  def description,
    do:
      "List a sandbox's available devices with their `id`, `name`, `platform` (such as `ios`), `runtime` (such as `iOS 27.2`) and `state` (`Booted`, `Shutdown`). Today these are the iOS and other Apple simulators of a macOS sandbox; Android emulators are not supported yet, and a Linux sandbox answers `devices_unsupported`. Resumes a paused sandbox. Requires an account member, or an administrator for a sandbox that serves an integration (an agent environment or Amp Orb)."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:devices, conn, args)
end

defmodule Tuist.MCP.Components.Tools.BootSandboxDevice do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "boot_sandbox_device",
    title: "Boot Sandbox Device",
    read_only_hint: false,
    destructive_hint: false,
    schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.inputs(:boot_device)),
    output_schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.response(:boot_device))

  @impl EMCP.Tool
  def description,
    do:
      "Boot a device in a sandbox, by name or ID from `list_sandbox_devices`, and wait up to 40 seconds for it to finish booting. Today this is an iOS simulator on a macOS sandbox, shown in the Simulator app; Android emulators are not supported yet. Booting a booted device succeeds. Returns the device; its `state` is still `Booting` when it took longer. Requires an account member, or an administrator for a sandbox that serves an integration (an agent environment or Amp Orb)."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:boot_device, conn, args)
end

defmodule Tuist.MCP.Components.Tools.LaunchSandboxApp do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "launch_sandbox_app",
    title: "Launch Sandbox App",
    read_only_hint: false,
    destructive_hint: false,
    schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.inputs(:launch_app)),
    output_schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.response(:launch_app))

  @impl EMCP.Tool
  def description,
    do:
      "Launch an app on a booted device of a sandbox, restarting it when it already runs. Today the device is an iOS simulator on a macOS sandbox. Pass `app_path`, an .app built in the sandbox, to install it first (its `app_id`, the bundle ID, is read from it), or `app_id` for an installed app. Build the app in the sandbox first, such as with `tuist sandbox exec <id> -- xcodebuild ... -derivedDataPath build/dd`. Requires an account member, or an administrator for a sandbox that serves an integration (an agent environment or Amp Orb)."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:launch_app, conn, args)
end

defmodule Tuist.MCP.Components.Tools.OpenSandboxURL do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "open_sandbox_url",
    title: "Open URL on Sandbox Device",
    read_only_hint: false,
    destructive_hint: false,
    schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.inputs(:open_url)),
    output_schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.response(:open_url))

  @impl EMCP.Tool
  def description,
    do:
      "Open a URL on a booted device of a sandbox: a web page in the browser (Safari on an iOS simulator), or an app's deep link to go to one of its screens. Today the device is an iOS simulator on a macOS sandbox. Requires an account member, or an administrator for a sandbox that serves an integration (an agent environment or Amp Orb)."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:open_url, conn, args)
end

defmodule Tuist.MCP.Components.Tools.GetSandboxScreenshot do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "get_sandbox_screenshot",
    title: "Get Sandbox Screenshot",
    read_only_hint: true,
    destructive_hint: false,
    schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.inputs(:screenshot)),
    output_schema: Tuist.Sandboxes.Schemas.json_schema(Tuist.Sandboxes.Schemas.response(:screenshot))

  alias Tuist.MCP.Components.Tools.SandboxTools
  alias Tuist.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "Capture a booted device of a sandbox (default), or with `target: screen` the sandbox's whole screen, and return it as an image, a JPEG at most 1600 pixels on its longer side. Today this works on macOS sandboxes, whose devices are iOS simulators. Use it to show the user the app running and to check what a change did. Fails with `device_not_booted` until a device is booted (`boot_sandbox_device`). Where the Tuist CLI runs, `tuist sandbox screenshot <id> --out shot.png` saves the full-size PNG instead. Requires an account member, or an administrator for a sandbox that serves an integration (an agent environment or Amp Orb)."

  @impl EMCP.Tool
  def call(conn, args) do
    with :ok <- Tool.validate_input(__MODULE__, args),
         {:ok, shot} <- SandboxTools.execute(:screenshot, conn, args) do
      {data, metadata} = Map.pop(shot, :data)
      result = Tool.json_response(metadata, __MODULE__)
      Map.update!(result, "content", &[%{"type" => "image", "data" => data, "mimeType" => shot.mime_type} | &1])
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end
end
