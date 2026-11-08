defmodule TuistWeb.API.SandboxesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Commands
  alias Tuist.Sandboxes.Query
  alias Tuist.Sandboxes.Schemas, as: SandboxSchemas
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.LoaderPlug)

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  # Members create sandboxes and run commands in them (`:sandboxes_use`).
  # Sandboxes that serve an agent environment, an Amp integration or remote
  # execution hold credentials or other people's work, so only admins reach
  # those, and everything else (agent environments, Orb dispatch, analytics,
  # archive) stays admin-only.
  @member_actions [
    :index,
    :create,
    :show,
    :exec,
    :start_command,
    :index_commands,
    :show_command,
    :stream_command_logs,
    :write_command_stdin,
    :cancel_command,
    :pause,
    :resume,
    :delete
  ]

  plug AuthorizationPlug, {:account, :sandboxes, :use} when action in @member_actions
  plug AuthorizationPlug, {:account, :account, :update} when action not in @member_actions
  plug(TuistWeb.Plugs.RequireSandboxesPlug)
  plug :require_member_sandbox when action in @member_actions

  tags ["Sandboxes"]

  @orb_admission_refusals [
    :no_capacity,
    :sandbox_concurrency_limit,
    :sandbox_disk_limit,
    :sandbox_account_busy,
    :locked
  ]

  @agent_environment_schema %Schema{
    title: "SandboxAgentEnvironment",
    description:
      "An Anthropic self-hosted environment served by the account's sandboxes: a Claude Managed Agents environment or a Claude Code cloud environment.",
    type: :object,
    properties: %{
      id: %Schema{type: :integer},
      kind: %Schema{type: :string, enum: ["managed_agents", "claude_code"], default: "managed_agents"},
      anthropic_environment_id: %Schema{type: :string},
      name: %Schema{type: :string, nullable: true},
      platform: %Schema{type: :string, enum: ["linux", "darwin"], default: "linux"},
      template: %Schema{type: :string},
      vcpus: %Schema{type: :integer},
      memory_mb: %Schema{type: :integer},
      workspace_gb: %Schema{type: :integer},
      max_idle_seconds: %Schema{type: :integer},
      pause_grace_seconds: %Schema{type: :integer},
      enabled: %Schema{type: :boolean},
      has_api_key: %Schema{
        type: :boolean,
        description: "Whether an Anthropic API key is stored, which is what lets Tuist start agent sessions."
      },
      anthropic_agent_id: %Schema{
        type: :string,
        nullable: true,
        description: "The Anthropic agent Tuist created for this environment's model and system prompt."
      },
      agent_model: %Schema{type: :string},
      agent_system_prompt: %Schema{type: :string, nullable: true},
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"}
    },
    required: [
      :id,
      :anthropic_environment_id,
      :platform,
      :template,
      :vcpus,
      :memory_mb,
      :workspace_gb,
      :max_idle_seconds,
      :pause_grace_seconds,
      :enabled,
      :has_api_key,
      :anthropic_agent_id,
      :agent_model,
      :agent_system_prompt,
      :inserted_at,
      :updated_at
    ]
  }

  @agent_properties %{
    anthropic_api_key: %Schema{
      type: :string,
      description: "An Anthropic API key with access to the environment's organization. Never returned."
    },
    agent_model: %Schema{type: :string, minLength: 1, maxLength: 255, description: "The model agent sessions run."},
    agent_system_prompt: %Schema{
      type: :string,
      maxLength: 100_000,
      nullable: true,
      description: "System prompt of the agent Tuist creates. Defaults to a sandbox-aware coding prompt."
    }
  }

  @sandbox_schema SandboxSchemas.sandbox()

  @exec_result_schema %Schema{
    title: "SandboxExecResult",
    type: :object,
    properties: %{
      exit_code: %Schema{type: :integer, nullable: true},
      stdout: %Schema{type: :string},
      stderr: %Schema{type: :string}
    },
    required: [:exit_code, :stdout, :stderr]
  }

  @account_parameters [
    account_handle: [in: :path, type: :string, required: true, description: "The account handle."]
  ]

  @sandbox_parameters @account_parameters ++
                        [sandbox_id: [in: :path, type: :string, required: true, description: "The sandbox identifier."]]

  @shape_properties SandboxSchemas.shape()

  @error_responses %{
    forbidden: {"Forbidden", "application/json", Error},
    too_many_requests: Responses.authorization_throttled()
  }

  @node_error_responses %{
    conflict: {"The sandbox is not in a state that allows the operation", "application/json", Error},
    bad_gateway: {"The sandbox node rejected the operation", "application/json", Error},
    service_unavailable: {"No sandbox node is available", "application/json", Error},
    gateway_timeout: {"The sandbox node did not answer in time", "application/json", Error}
  }

  operation(:dispatch_amp_orb,
    summary: "Dispatch a self-hosted Amp Orb lifecycle job.",
    description:
      "Idempotently spawns, pauses or deletes an account's Orb. Uses the installed Firecracker template; arbitrary OCI images are not imported. A pause with `snapshot_id` saves the Orb's disks as a project snapshot, and a spawn of a new Orb with a saved `snapshot_id` starts from it.",
    operation_id: "dispatchAmpOrb",
    parameters:
      @account_parameters ++
        [
          orb_id: [
            in: :path,
            required: true,
            schema: %Schema{type: :string, minLength: 1, maxLength: 255, pattern: "^[a-zA-Z0-9_-]+$"}
          ]
        ],
    request_body:
      {"Orb job", "application/json",
       %Schema{
         title: "DispatchAmpOrb",
         type: :object,
         properties:
           Map.merge(@shape_properties, %{
             operation: %Schema{type: :string, enum: ["spawn", "pause", "delete"]},
             orb_token: %Schema{type: :string, minLength: 1, maxLength: 16_384, writeOnly: true},
             amp_url: %Schema{type: :string, format: :uri, pattern: "^https://", maxLength: 2048},
             snapshot_id: %Schema{
               type: :string,
               pattern: "^[A-Za-z0-9._:-]{1,255}$",
               description: "Amp's project snapshot identifier (ORB_SNAPSHOT_ID)."
             }
           }),
         required: [:operation]
       }},
    responses:
      @error_responses
      |> Map.merge(@node_error_responses)
      |> Map.merge(%{
        no_content: "The Orb operation completed",
        bad_request: {"Invalid job", "application/json", Error}
      })
  )

  def dispatch_amp_orb(
        %{assigns: %{selected_account: account}, params: %{orb_id: orb_id}, body_params: params} = conn,
        _params
      ) do
    if params.operation == "spawn" and is_nil(Map.get(params, :orb_token)) do
      conn |> put_status(:bad_request) |> json(%{message: "orb_token is required for spawn."})
    else
      case Sandboxes.dispatch_amp_orb(account, orb_id, params) do
        {:ok, _sandbox} ->
          send_resp(conn, :no_content, "")

        {:error, :orb_bootstrap_failed} ->
          conn |> put_status(:bad_gateway) |> json(%{message: "Orb bootstrap failed. Check the sandbox image."})

        {:error, reason} when reason in @orb_admission_refusals ->
          conn |> put_resp_header("x-tuist-orb-retry", "admission") |> sandbox_error(reason)

        {:error, reason} ->
          sandbox_error(conn, reason)
      end
    end
  end

  operation(:create_agent_environment,
    summary: "Connect an Anthropic self-hosted environment to the account.",
    description:
      "Stores the environment key encrypted and starts serving the environment's work queue with sandboxes shaped by the given template and resources.",
    operation_id: "createSandboxAgentEnvironment",
    parameters: @account_parameters,
    request_body:
      {"Agent environment params", "application/json",
       %Schema{
         title: "CreateSandboxAgentEnvironment",
         type: :object,
         properties:
           @shape_properties
           |> Map.merge(@agent_properties)
           |> Map.merge(%{
             kind: %Schema{
               type: :string,
               enum: ["managed_agents", "claude_code"],
               default: "managed_agents",
               description:
                 "managed_agents connects a Claude Managed Agents environment (env_...); claude_code connects a Claude Code cloud environment (ccpool_...), whose sessions started from Claude Code on the web, desktop, mobile or CLI run in the account's sandboxes on the environment's platform."
             },
             anthropic_environment_id: %Schema{
               type: :string,
               description: "The Anthropic environment identifier: env_... or, for claude_code, ccpool_..."
             },
             environment_key: %Schema{
               type: :string,
               description:
                 "The environment key: the Managed Agents environment key, or the Claude Code environment secret. Never returned."
             },
             name: %Schema{type: :string, maxLength: 100, nullable: true},
             max_idle_seconds: %Schema{type: :integer, minimum: 1, maximum: 3600},
             pause_grace_seconds: %Schema{type: :integer, minimum: 0, maximum: 3600}
           }),
         required: [:anthropic_environment_id, :environment_key]
       }},
    responses:
      Map.merge(@error_responses, %{
        created: {"Agent environment", "application/json", @agent_environment_schema},
        bad_request: {"Invalid params", "application/json", Error}
      })
  )

  def create_agent_environment(%{assigns: %{selected_account: account}, body_params: body_params} = conn, _params) do
    attrs =
      Map.take(body_params, [
        :kind,
        :anthropic_environment_id,
        :environment_key,
        :anthropic_api_key,
        :agent_model,
        :agent_system_prompt,
        :name,
        :platform,
        :template,
        :vcpus,
        :memory_mb,
        :workspace_gb,
        :max_idle_seconds,
        :pause_grace_seconds
      ])

    case Sandboxes.create_agent_environment(account, attrs) do
      {:ok, agent_environment} ->
        conn |> put_status(:created) |> json(serialize_agent_environment(agent_environment))

      {:error, %Ecto.Changeset{} = changeset} ->
        sandbox_error(conn, changeset)
    end
  end

  operation(:update_agent_environment,
    summary: "Update the agent settings of a connected environment.",
    description:
      "Sets the Anthropic API key Tuist uses to start agent sessions, the model and the system prompt. Changing the model or the prompt drops the cached agent so the next session creates a new one.",
    operation_id: "updateSandboxAgentEnvironment",
    parameters:
      @account_parameters ++
        [agent_environment_id: [in: :path, type: :integer, required: true, description: "The agent environment id."]],
    request_body:
      {"Agent environment params", "application/json",
       %Schema{title: "UpdateSandboxAgentEnvironment", type: :object, properties: @agent_properties}},
    responses:
      Map.merge(@error_responses, %{
        ok: {"Agent environment", "application/json", @agent_environment_schema},
        bad_request: {"Invalid params", "application/json", Error},
        not_found: {"The agent environment was not found", "application/json", Error}
      })
  )

  def update_agent_environment(
        %{
          assigns: %{selected_account: account},
          params: %{agent_environment_id: agent_environment_id},
          body_params: body_params
        } = conn,
        _params
      ) do
    attrs = Map.take(body_params, [:anthropic_api_key, :agent_model, :agent_system_prompt])

    with {:ok, agent_environment} <- Sandboxes.get_agent_environment(account, agent_environment_id),
         {:ok, agent_environment} <- Sandboxes.update_agent_environment(agent_environment, attrs) do
      json(conn, serialize_agent_environment(agent_environment))
    else
      {:error, :not_found} -> not_found(conn, "Agent environment not found.")
      {:error, %Ecto.Changeset{} = changeset} -> sandbox_error(conn, changeset)
    end
  end

  operation(:index_agent_environments,
    summary: "List the Anthropic environments connected to the account.",
    operation_id: "listSandboxAgentEnvironments",
    parameters: @account_parameters,
    responses:
      Map.put(
        @error_responses,
        :ok,
        {"Agent environments", "application/json",
         %Schema{
           type: :object,
           properties: %{agent_environments: %Schema{type: :array, items: @agent_environment_schema}},
           required: [:agent_environments]
         }}
      )
  )

  def index_agent_environments(%{assigns: %{selected_account: account}} = conn, _params) do
    json(conn, %{
      agent_environments: account |> Sandboxes.list_agent_environments() |> Enum.map(&serialize_agent_environment/1)
    })
  end

  operation(:delete_agent_environment,
    summary: "Disconnect an Anthropic environment and delete its sandboxes.",
    operation_id: "deleteSandboxAgentEnvironment",
    parameters:
      @account_parameters ++
        [agent_environment_id: [in: :path, type: :integer, required: true, description: "The agent environment id."]],
    responses:
      Map.merge(@error_responses, %{
        no_content: "The agent environment was deleted",
        not_found: {"The agent environment was not found", "application/json", Error}
      })
  )

  def delete_agent_environment(
        %{assigns: %{selected_account: account}, params: %{agent_environment_id: agent_environment_id}} = conn,
        _params
      ) do
    with {:ok, agent_environment} <- Sandboxes.get_agent_environment(account, agent_environment_id),
         {:ok, _deleted} <- Sandboxes.delete_agent_environment(agent_environment) do
      send_resp(conn, :no_content, "")
    else
      {:error, :not_found} -> not_found(conn, "Agent environment not found.")
      {:error, reason} -> sandbox_error(conn, reason)
    end
  end

  operation(:index,
    summary: "List the account's sandboxes.",
    description: "Newest first by default. Deleted sandboxes are not listed.",
    operation_id: "listSandboxes",
    parameters: SandboxSchemas.parameters(:list),
    responses:
      Map.merge(@error_responses, %{
        ok: {"Sandboxes", "application/json", SandboxSchemas.response(:list)},
        bad_request: {"Invalid parameters", "application/json", Error}
      })
  )

  def index(%{assigns: %{selected_account: account}} = conn, params),
    do: respond(conn, Query.run(:list, account, string_keys(params)))

  operation(:analytics,
    summary: "Get the account's sandbox analytics for a time range.",
    description:
      "vCPU-hours, sandboxes created, session, setup and time-to-start durations, and peak vCPUs, memory and disk against the account's limits, each with its trend against the range of the same length before it. Defaults to the last 30 days; the maximum range is 90 days.",
    operation_id: "getSandboxAnalytics",
    parameters: SandboxSchemas.parameters(:analytics),
    responses:
      Map.merge(@error_responses, %{
        ok: {"Sandbox analytics", "application/json", SandboxSchemas.response(:analytics)},
        bad_request: {"Invalid parameters", "application/json", Error}
      })
  )

  def analytics(%{assigns: %{selected_account: account}} = conn, params),
    do: respond(conn, Query.run(:analytics, account, string_keys(params)))

  operation(:create,
    summary: "Create a sandbox.",
    description:
      "Boots a bare sandbox VM from the template. Useful to validate a template before connecting an environment.",
    operation_id: "createSandbox",
    parameters: @account_parameters,
    request_body:
      {"Sandbox params", "application/json",
       %Schema{title: "CreateSandbox", type: :object, properties: @shape_properties}},
    responses:
      @error_responses
      |> Map.merge(@node_error_responses)
      |> Map.merge(%{
        created: {"Sandbox", "application/json", @sandbox_schema},
        bad_request: {"Invalid params", "application/json", Error}
      })
  )

  def create(%{assigns: %{selected_account: account}, body_params: body_params} = conn, _params) do
    case Query.run(:create, account, string_keys(body_params)) do
      {:ok, sandbox} -> conn |> put_status(:created) |> json(sandbox)
      {:error, reason} -> sandbox_error(conn, reason)
    end
  end

  operation(:show,
    summary: "Get a sandbox.",
    operation_id: "getSandbox",
    parameters: @sandbox_parameters,
    responses:
      Map.merge(@error_responses, %{
        ok: {"Sandbox", "application/json", @sandbox_schema},
        not_found: {"The sandbox was not found", "application/json", Error}
      })
  )

  def show(%{assigns: %{selected_account: account}} = conn, params),
    do: respond(conn, Query.run(:show, account, string_keys(params)))

  operation(:exec,
    summary: "Run a shell command in a sandbox.",
    description:
      "Runs the command with `/bin/bash -lc` inside the sandbox, resuming it first when paused, and returns the exit code with the captured output (capped at 1 MiB per stream).",
    operation_id: "execSandboxCommand",
    parameters: @sandbox_parameters,
    request_body:
      {"Command params", "application/json",
       %Schema{
         title: "ExecSandboxCommand",
         type: :object,
         properties: %{
           command: %Schema{type: :string, minLength: 1, description: "The shell command to run."},
           timeout_ms: %Schema{
             type: :integer,
             minimum: 1,
             maximum: 600_000,
             description: "Kill the command after this many milliseconds (default 60000)."
           }
         },
         required: [:command]
       }},
    responses:
      @error_responses
      |> Map.merge(@node_error_responses)
      |> Map.merge(%{
        ok: {"Command result", "application/json", @exec_result_schema},
        not_found: {"The sandbox was not found", "application/json", Error}
      })
  )

  def exec(
        %{assigns: %{selected_account: account}, params: %{sandbox_id: sandbox_id}, body_params: body_params} = conn,
        _params
      ) do
    with_sandbox(conn, account, sandbox_id, fn sandbox ->
      opts = if timeout_ms = Map.get(body_params, :timeout_ms), do: [timeout_ms: timeout_ms], else: []

      case Sandboxes.exec(sandbox, ["/bin/bash", "-lc", body_params.command], opts) do
        {:ok, result} -> json(conn, Map.take(result, [:exit_code, :stdout, :stderr]))
        {:error, reason} -> sandbox_error(conn, reason)
      end
    end)
  end

  @command_schema %Schema{
    title: "SandboxCommand",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      command: %Schema{type: :string, description: "The shell script the command runs; argv commands appear quoted."},
      cwd: %Schema{type: :string, nullable: true},
      stdin: %Schema{type: :boolean, description: "Whether stdin stays open for `POST .../stdin`."},
      status: %Schema{
        type: :string,
        enum: ["running", "exited", "timed_out", "cancelled", "lost"],
        description: "`lost` means the command's process is gone without an exit code, such as after the guest restarted."
      },
      exit_code: %Schema{type: :integer, nullable: true},
      started_at: %Schema{type: :string, format: "date-time"},
      deadline_at: %Schema{type: :string, format: "date-time"},
      finished_at: %Schema{type: :string, format: "date-time", nullable: true}
    },
    required: [:id, :command, :stdin, :status, :started_at, :deadline_at]
  }

  @command_log_line_schema %Schema{
    title: "SandboxCommandLogLine",
    description:
      "One line of the ND-JSON log stream. `stdout` and `stderr` lines carry output and `offset`, the byte offset the stream reached, which a reconnect passes back as `stdout_offset` or `stderr_offset`. The last line is `exit`, with the command's final state, or `error`.",
    type: :object,
    properties: %{
      type: %Schema{type: :string, enum: ["stdout", "stderr", "exit", "error"]},
      data: %Schema{type: :string},
      offset: %Schema{type: :integer},
      status: %Schema{type: :string},
      exit_code: %Schema{type: :integer, nullable: true},
      message: %Schema{type: :string}
    },
    required: [:type]
  }

  @command_parameters @sandbox_parameters ++
                        [command_id: [in: :path, type: :string, required: true, description: "The command identifier."]]

  operation(:start_command,
    summary: "Start a command in a sandbox.",
    description:
      "Starts the command detached in the sandbox, resuming it first, and answers at once. Stream its output with `GET .../commands/:command_id/logs`. A sandbox runs several commands at once; while any runs, it is not paused for idleness. An agent turn holding the sandbox refuses commands with 409.",
    operation_id: "startSandboxCommand",
    parameters: @sandbox_parameters,
    request_body:
      {"Command params", "application/json",
       %Schema{
         title: "StartSandboxCommand",
         type: :object,
         properties: %{
           command: %Schema{
             type: :string,
             minLength: 1,
             description: "A shell script run with `/bin/bash -l`, or the program to run when `args` is given."
           },
           args: %Schema{
             type: :array,
             items: %Schema{type: :string},
             description: "Run `command` with these arguments directly, without shell interpretation."
           },
           env: %Schema{
             type: :object,
             additionalProperties: %Schema{type: :string},
             description: "Environment variables for the command. Never stored."
           },
           cwd: %Schema{type: :string, description: "Working directory. Defaults to the sandbox's workspace."},
           stdin: %Schema{
             type: :boolean,
             description: "Keep stdin open for `POST .../stdin`. Otherwise the command reads an empty stdin."
           },
           timeout_ms: %Schema{
             type: :integer,
             minimum: 1,
             maximum: 21_600_000,
             description: "Kill the command after this many milliseconds (default one hour)."
           }
         },
         required: [:command]
       }},
    responses:
      @error_responses
      |> Map.merge(@node_error_responses)
      |> Map.merge(%{
        bad_request: {"The parameters are invalid", "application/json", Error},
        accepted: {"The command started", "application/json", @command_schema},
        not_found: {"The sandbox was not found", "application/json", Error}
      })
  )

  def start_command(
        %{assigns: %{selected_account: account}, params: %{sandbox_id: sandbox_id}, body_params: body_params} = conn,
        _params
      ) do
    with_sandbox(conn, account, sandbox_id, fn sandbox ->
      params = Map.take(body_params, [:command, :args, :env, :cwd, :stdin, :timeout_ms])

      case Commands.start(sandbox, params) do
        {:ok, command} -> conn |> put_status(:accepted) |> json(command)
        {:error, reason} -> sandbox_error(conn, reason)
      end
    end)
  end

  operation(:index_commands,
    summary: "List a sandbox's commands.",
    description: "The 100 most recent commands, newest first. Finished commands are kept for seven days.",
    operation_id: "listSandboxCommands",
    parameters: @sandbox_parameters,
    responses:
      Map.merge(@error_responses, %{
        ok:
          {"Commands", "application/json",
           %Schema{
             title: "SandboxCommands",
             type: :object,
             properties: %{commands: %Schema{type: :array, items: @command_schema}},
             required: [:commands]
           }},
        not_found: {"The sandbox was not found", "application/json", Error}
      })
  )

  def index_commands(%{assigns: %{selected_account: account}, params: %{sandbox_id: sandbox_id}} = conn, _params) do
    with_sandbox(conn, account, sandbox_id, fn sandbox -> json(conn, %{commands: Commands.list(sandbox)}) end)
  end

  operation(:show_command,
    summary: "Get a sandbox command.",
    description: "With `wait_seconds`, waits until the command ends or the time passes.",
    operation_id: "getSandboxCommand",
    parameters:
      @command_parameters ++
        [
          wait_seconds: [
            in: :query,
            type: :integer,
            description: "Wait up to this long for the command to end, at most 50."
          ]
        ],
    responses:
      @error_responses
      |> Map.merge(@node_error_responses)
      |> Map.merge(%{
        ok: {"Command", "application/json", @command_schema},
        not_found: {"The sandbox or command was not found", "application/json", Error}
      })
  )

  def show_command(%{assigns: %{selected_account: account}, params: %{sandbox_id: sandbox_id} = params} = conn, _params) do
    with_sandbox(conn, account, sandbox_id, fn sandbox ->
      case Commands.wait(sandbox, params.command_id, Map.get(params, :wait_seconds, 0)) do
        {:ok, command} -> json(conn, command)
        {:error, :not_found} -> not_found(conn, "Command not found.")
        {:error, reason} -> sandbox_error(conn, reason)
      end
    end)
  end

  operation(:stream_command_logs,
    summary: "Stream a sandbox command's output.",
    description:
      "Streams the command's stdout and stderr as newline-delimited JSON (`application/x-ndjson`) from the given byte offsets until the command ends, then a final `exit` line. The server ends a stream after about 50 minutes without an `exit` line; reconnect with the last offsets to continue.",
    operation_id: "streamSandboxCommandLogs",
    parameters:
      @command_parameters ++
        [
          stdout_offset: [in: :query, type: :integer, description: "Byte offset to stream stdout from (default 0)."],
          stderr_offset: [in: :query, type: :integer, description: "Byte offset to stream stderr from (default 0)."]
        ],
    responses:
      @error_responses
      |> Map.merge(@node_error_responses)
      |> Map.merge(%{
        ok: {"Log lines", "application/x-ndjson", @command_log_line_schema},
        not_found: {"The sandbox or command was not found", "application/json", Error}
      })
  )

  # Each read waits at most this long, which keeps every chunk well inside the
  # ~100 second idle timeout of Cloudflare and other proxies.
  @log_wait_seconds 25
  @log_stream_ms to_timeout(minute: 50)

  def stream_command_logs(
        %{assigns: %{selected_account: account}, params: %{sandbox_id: sandbox_id} = params} = conn,
        _params
      ) do
    with_sandbox(conn, account, sandbox_id, fn sandbox ->
      offsets = {Map.get(params, :stdout_offset, 0), Map.get(params, :stderr_offset, 0)}

      # The first read answers before the response starts, so an unknown
      # command or an unreachable sandbox is a plain error status.
      case read_logs(sandbox, params.command_id, offsets, 0) do
        {:ok, read} ->
          conn =
            conn
            |> put_resp_content_type("application/x-ndjson")
            |> put_resp_header("cache-control", "no-store")
            |> put_resp_header("x-accel-buffering", "no")
            |> send_chunked(:ok)

          stream_logs(conn, sandbox, params.command_id, read, System.monotonic_time(:millisecond) + @log_stream_ms)

        {:error, :not_found} ->
          not_found(conn, "Command not found.")

        {:error, reason} ->
          sandbox_error(conn, reason)
      end
    end)
  end

  defp read_logs(sandbox, id, {stdout_offset, stderr_offset}, wait),
    do: Commands.read(sandbox, id, stdout_offset: stdout_offset, stderr_offset: stderr_offset, wait_seconds: wait)

  defp stream_logs(conn, sandbox, id, read, deadline) do
    case send_lines(conn, log_lines(read)) do
      {:ok, conn} ->
        if read.complete or System.monotonic_time(:millisecond) >= deadline,
          do: conn,
          else: continue_logs(conn, sandbox, id, read, deadline)

      # The client went away.
      {:error, _reason} ->
        conn
    end
  end

  defp continue_logs(conn, sandbox, id, read, deadline) do
    case read_logs(sandbox, id, {read.stdout_offset, read.stderr_offset}, @log_wait_seconds) do
      {:ok, next} ->
        stream_logs(conn, sandbox, id, next, deadline)

      {:error, reason} ->
        message = if reason == :not_found, do: "Command not found.", else: reason |> Query.error() |> elem(1)
        {_result, conn} = send_lines(conn, [%{type: "error", message: message}])
        conn
    end
  end

  defp log_lines(read) do
    Enum.filter(
      [
        read.stdout != "" && %{type: "stdout", data: read.stdout, offset: read.stdout_offset},
        read.stderr != "" && %{type: "stderr", data: read.stderr, offset: read.stderr_offset},
        read.complete && %{type: "exit", status: read.status, exit_code: read.exit_code}
      ],
      & &1
    )
  end

  defp send_lines(conn, []), do: {:ok, conn}
  defp send_lines(conn, lines), do: chunk(conn, Enum.map(lines, &[JSON.encode!(&1), ?\n]))

  operation(:write_command_stdin,
    summary: "Write to a sandbox command's stdin.",
    description:
      "Appends the data to the stdin of a command started with `stdin: true`. With `close`, ends its stdin after the data.",
    operation_id: "writeSandboxCommandStdin",
    parameters: @command_parameters,
    request_body:
      {"Stdin params", "application/json",
       %Schema{
         title: "WriteSandboxCommandStdin",
         type: :object,
         properties: %{
           data: %Schema{type: :string, format: :byte, description: "Base64-encoded bytes, at most 256 KiB decoded."},
           close: %Schema{type: :boolean, description: "End the command's stdin after the data."}
         }
       }},
    responses:
      @error_responses
      |> Map.merge(@node_error_responses)
      |> Map.merge(%{
        bad_request: {"The data is not base64 or is too large", "application/json", Error},
        ok: {"Command", "application/json", @command_schema},
        not_found: {"The sandbox or command was not found", "application/json", Error}
      })
  )

  def write_command_stdin(
        %{assigns: %{selected_account: account}, params: %{sandbox_id: sandbox_id} = params, body_params: body_params} =
          conn,
        _params
      ) do
    with_sandbox(conn, account, sandbox_id, fn sandbox ->
      with {:ok, data} <- Base.decode64(Map.get(body_params, :data) || ""),
           {:ok, command} <- Commands.write_stdin(sandbox, params.command_id, data, Map.get(body_params, :close) == true) do
        json(conn, command)
      else
        :error -> sandbox_error(conn, :invalid_command)
        {:error, :not_found} -> not_found(conn, "Command not found.")
        {:error, reason} -> sandbox_error(conn, reason)
      end
    end)
  end

  operation(:cancel_command,
    summary: "Stop a sandbox command.",
    description: "Sends SIGTERM to the command's process group, then SIGKILL after five seconds.",
    operation_id: "cancelSandboxCommand",
    parameters: @command_parameters,
    responses:
      @error_responses
      |> Map.merge(@node_error_responses)
      |> Map.merge(%{
        ok: {"Command", "application/json", @command_schema},
        not_found: {"The sandbox or command was not found", "application/json", Error}
      })
  )

  def cancel_command(%{assigns: %{selected_account: account}, params: %{sandbox_id: sandbox_id} = params} = conn, _params) do
    with_sandbox(conn, account, sandbox_id, fn sandbox ->
      case Commands.cancel(sandbox, params.command_id) do
        {:ok, command} -> json(conn, command)
        {:error, :not_found} -> not_found(conn, "Command not found.")
        {:error, reason} -> sandbox_error(conn, reason)
      end
    end)
  end

  operation(:pause,
    summary: "Pause a sandbox.",
    description: "Snapshots the VM to the node's disk. Refused while a worker or command is running.",
    operation_id: "pauseSandbox",
    parameters: @sandbox_parameters,
    responses:
      @error_responses
      |> Map.merge(@node_error_responses)
      |> Map.merge(%{
        ok: {"Sandbox", "application/json", @sandbox_schema},
        not_found: {"The sandbox was not found", "application/json", Error}
      })
  )

  def pause(%{assigns: %{selected_account: account}} = conn, params),
    do: respond(conn, Query.run(:pause, account, string_keys(params)))

  operation(:resume,
    summary: "Resume a paused sandbox.",
    operation_id: "resumeSandbox",
    parameters: @sandbox_parameters,
    responses:
      @error_responses
      |> Map.merge(@node_error_responses)
      |> Map.merge(%{
        ok: {"Sandbox", "application/json", @sandbox_schema},
        not_found: {"The sandbox was not found", "application/json", Error}
      })
  )

  def resume(%{assigns: %{selected_account: account}} = conn, params),
    do: respond(conn, Query.run(:resume, account, string_keys(params)))

  operation(:delete,
    summary: "Delete a sandbox.",
    operation_id: "deleteSandbox",
    parameters: @sandbox_parameters,
    responses:
      @error_responses
      |> Map.merge(@node_error_responses)
      |> Map.merge(%{
        no_content: "The sandbox was deleted",
        not_found: {"The sandbox was not found", "application/json", Error}
      })
  )

  def delete(%{assigns: %{selected_account: account}} = conn, params) do
    case Query.run(:delete, account, string_keys(params)) do
      {:ok, _deleted} -> send_resp(conn, :no_content, "")
      error -> respond(conn, error)
    end
  end

  operation(:archive,
    summary: "Archive a paused sandbox.",
    description:
      "Queues moving the paused sandbox's disks to object storage, which frees them on its node. The sandbox stays `paused` until the upload completes and then becomes `archived`; resuming restores it.",
    operation_id: "archiveSandbox",
    parameters: @sandbox_parameters,
    responses:
      @error_responses
      |> Map.merge(@node_error_responses)
      |> Map.merge(%{
        accepted: {"Sandbox", "application/json", @sandbox_schema},
        not_found: {"The sandbox was not found", "application/json", Error}
      })
  )

  def archive(%{assigns: %{selected_account: account}} = conn, params) do
    case Query.run(:archive, account, string_keys(params)) do
      {:ok, sandbox} -> conn |> put_status(:accepted) |> json(sandbox)
      error -> respond(conn, error)
    end
  end

  # CastAndValidate casts the params to atom keys; Query takes the string
  # keys MCP tools receive.
  defp string_keys(params), do: Map.new(params, fn {key, value} -> {to_string(key), value} end)

  defp respond(conn, {:ok, data}), do: json(conn, data)
  defp respond(conn, {:error, reason}), do: sandbox_error(conn, reason)

  defp with_sandbox(conn, account, sandbox_id, fun) do
    case Sandboxes.get_sandbox(account, sandbox_id) do
      {:ok, sandbox} -> fun.(sandbox)
      {:error, :not_found} -> not_found(conn, "Sandbox not found.")
    end
  end

  defp not_found(conn, message), do: conn |> put_status(:not_found) |> json(%{message: message})

  # A member reaches only the sandboxes they could have created: none that
  # serves an agent environment, an Amp integration or remote execution.
  defp require_member_sandbox(%{assigns: %{selected_account: account}} = conn, _opts) do
    subject = TuistWeb.Authentication.authenticated_subject(conn)

    with %{sandbox_id: sandbox_id} <- conn.params,
         false <- Tuist.Authorization.authorize(:account_update, subject, account) == :ok,
         {:ok, sandbox} <- Sandboxes.get_sandbox(account, sandbox_id),
         false <- member_sandbox?(sandbox) do
      conn
      |> put_status(:forbidden)
      |> json(%{message: "Only account administrators can use sandboxes that serve agents, Amp or remote execution."})
      |> halt()
    else
      _ -> conn
    end
  end

  defp member_sandbox?(sandbox),
    do:
      is_nil(sandbox.agent_environment_id) and is_nil(sandbox.amp_integration_id) and
        is_nil(sandbox.provider_environment_id) and sandbox.purpose == :agent

  # Every sandbox 503 comes after the server has already waited for a node or
  # for capacity, so an immediate retry only repeats that wait. The hint is
  # longer than any client retry budget (`RetryMiddleware` waits at most 30
  # seconds per retry, 10 retries at most), so the CLI reports it at once.
  @service_unavailable_retry_after_seconds 300

  defp sandbox_error(conn, reason) do
    {status, message} = Query.error(reason)

    conn |> retry_after(status) |> put_status(status) |> json(%{message: message})
  end

  defp retry_after(conn, :service_unavailable),
    do: put_resp_header(conn, "retry-after", "#{@service_unavailable_retry_after_seconds}")

  defp retry_after(conn, _status), do: conn

  defp serialize_agent_environment(%AgentEnvironment{} = agent_environment) do
    agent_environment
    |> Map.take([
      :id,
      :kind,
      :anthropic_environment_id,
      :name,
      :platform,
      :template,
      :vcpus,
      :memory_mb,
      :workspace_gb,
      :max_idle_seconds,
      :pause_grace_seconds,
      :enabled,
      :anthropic_agent_id,
      :agent_model,
      :agent_system_prompt,
      :inserted_at,
      :updated_at
    ])
    |> Map.put(:has_api_key, is_binary(agent_environment.anthropic_api_key))
  end
end
