defmodule Tuist.MCP.Components.Tools.SandboxTools do
  @moduledoc false
  alias Tuist.FeatureFlags
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Sandboxes.Query

  # Sandboxes run arbitrary commands and hold agent credentials, so, as in
  # the HTTP API, every tool, including the read-only ones, requires an
  # account administrator.
  def execute(action, conn, args) do
    with {:ok, account} <- MCPTool.resolve_and_authorize_account(args, conn.assigns, :update, :account),
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
      "List an account's sandboxes, newest first by default, with their status, shape and timestamps. Filter by status, vCPUs or text in the sandbox, Amp Orb or Anthropic session ID. Requires account administration."

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
  def description, do: "Get a sandbox's status, shape, node, archive and timestamps. Requires account administration."

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
      "Get an account's sandbox vCPU-hours, sandboxes created, session, setup and time-to-start durations, and peak vCPUs, memory and disk against its limits for a time range, with trends against the previous range. Defaults to the last 30 days; maximum range is 90 days."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:analytics, conn, args)
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
      "Pause a running sandbox: its VM is snapshotted to its node's disk and stops using vCPUs and memory. Refused while a worker or command runs."

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
  def description, do: "Resume a paused or archived sandbox. An archived one is restored from object storage first."

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
      "Queue moving a paused sandbox's disks to object storage, freeing them on its node. It stays paused until the upload completes, then becomes archived; resuming restores it."

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
    do: "Delete a sandbox and its disks after user confirmation. This cannot be undone. Requires account administration."

  def execute(conn, args), do: Tuist.MCP.Components.Tools.SandboxTools.execute(:delete, conn, args)
end
