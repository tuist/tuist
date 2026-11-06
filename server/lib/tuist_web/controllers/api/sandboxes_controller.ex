defmodule TuistWeb.API.SandboxesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Anthropic.Federation
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

  # Sandboxes execute arbitrary commands and hold Anthropic credentials,
  # so every action, including the read-only ones, requires an account
  # administrator.
  plug AuthorizationPlug, {:account, :account, :update}
  plug(TuistWeb.Plugs.RequireSandboxesPlug)

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
        description:
          "Whether an Anthropic API key is stored. Tuist starts agent sessions with it unless the federation ids are set."
      },
      anthropic_organization_id: %Schema{type: :string, nullable: true},
      anthropic_workspace_id: %Schema{type: :string, nullable: true},
      anthropic_service_account_id: %Schema{type: :string, nullable: true},
      anthropic_federation_rule_id: %Schema{type: :string, nullable: true},
      federation_issuer_url: %Schema{
        type: :string,
        description:
          "The account's OpenID Connect issuer to register as a Custom OIDC federation issuer in the Claude Console."
      },
      federation_subject: %Schema{
        type: :string,
        description: "The sub claim of the tokens Tuist signs for this environment."
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
      :anthropic_organization_id,
      :anthropic_workspace_id,
      :anthropic_service_account_id,
      :anthropic_federation_rule_id,
      :federation_issuer_url,
      :federation_subject,
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
    anthropic_organization_id: %Schema{
      type: :string,
      nullable: true,
      description:
        "Workload Identity Federation: the Anthropic organization UUID. Set it with the other three federation ids to start sessions without an API key."
    },
    anthropic_workspace_id: %Schema{
      type: :string,
      nullable: true,
      description: "Workload Identity Federation: the workspace (wrkspc_...) the minted tokens are scoped to."
    },
    anthropic_service_account_id: %Schema{
      type: :string,
      nullable: true,
      description: "Workload Identity Federation: the service account (svac_...) the tokens act as."
    },
    anthropic_federation_rule_id: %Schema{
      type: :string,
      nullable: true,
      description:
        "Workload Identity Federation: the federation rule (fdrl_...) that maps Tuist's tokens to the service account."
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
        :anthropic_organization_id,
        :anthropic_workspace_id,
        :anthropic_service_account_id,
        :anthropic_federation_rule_id,
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
      "Sets how Tuist authenticates to Anthropic to start agent sessions (an API key, or the four Workload Identity Federation ids, which take precedence), the model and the system prompt. Changing the model or the prompt drops the cached agent so the next session creates a new one.",
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
    attrs =
      Map.take(body_params, [
        :anthropic_api_key,
        :agent_model,
        :agent_system_prompt | AgentEnvironment.federation_fields()
      ])

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
      :anthropic_organization_id,
      :anthropic_workspace_id,
      :anthropic_service_account_id,
      :anthropic_federation_rule_id,
      :anthropic_agent_id,
      :agent_model,
      :agent_system_prompt,
      :inserted_at,
      :updated_at
    ])
    |> Map.put(:has_api_key, is_binary(agent_environment.anthropic_api_key))
    |> Map.put(:federation_issuer_url, Federation.issuer(agent_environment.account_id))
    |> Map.put(:federation_subject, Federation.subject(agent_environment))
  end
end
