defmodule TuistWeb.API.SandboxesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Sandbox
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

  tags ["Sandboxes"]

  @template_pattern "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$"

  @agent_environment_schema %Schema{
    title: "SandboxAgentEnvironment",
    description: "An Anthropic Managed Agents self-hosted environment served by the account's sandboxes.",
    type: :object,
    properties: %{
      id: %Schema{type: :integer},
      anthropic_environment_id: %Schema{type: :string},
      name: %Schema{type: :string, nullable: true},
      template: %Schema{type: :string},
      vcpus: %Schema{type: :integer},
      memory_mb: %Schema{type: :integer},
      workspace_gb: %Schema{type: :integer},
      max_idle_seconds: %Schema{type: :integer},
      pause_grace_seconds: %Schema{type: :integer},
      enabled: %Schema{type: :boolean},
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"}
    },
    required: [
      :id,
      :anthropic_environment_id,
      :template,
      :vcpus,
      :memory_mb,
      :workspace_gb,
      :max_idle_seconds,
      :pause_grace_seconds,
      :enabled,
      :inserted_at,
      :updated_at
    ]
  }

  @sandbox_schema %Schema{
    title: "Sandbox",
    description: "A Firecracker sandbox VM.",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: "uuid"},
      state: %Schema{type: :string, enum: Enum.map(Sandbox.states(), &Atom.to_string/1)},
      template: %Schema{type: :string},
      template_tag: %Schema{type: :string, nullable: true},
      vcpus: %Schema{type: :integer},
      memory_mb: %Schema{type: :integer},
      workspace_gb: %Schema{type: :integer},
      node_name: %Schema{type: :string, nullable: true},
      hostname: %Schema{type: :string, nullable: true},
      agent_environment_id: %Schema{type: :integer, nullable: true},
      anthropic_session_id: %Schema{type: :string, nullable: true},
      residency_work_id: %Schema{type: :string, nullable: true},
      last_active_at: %Schema{type: :string, format: "date-time", nullable: true},
      paused_at: %Schema{type: :string, format: "date-time", nullable: true},
      error_message: %Schema{type: :string, nullable: true},
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"}
    },
    required: [:id, :state, :template, :vcpus, :memory_mb, :workspace_gb, :inserted_at, :updated_at]
  }

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

  @shape_properties %{
    template: %Schema{type: :string, pattern: @template_pattern, description: "Sandbox template name."},
    vcpus: %Schema{type: :integer, minimum: 1, maximum: 64},
    memory_mb: %Schema{type: :integer, minimum: 256, maximum: 262_144},
    workspace_gb: %Schema{type: :integer, minimum: 1, maximum: 1024}
  }

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
           Map.merge(@shape_properties, %{
             anthropic_environment_id: %Schema{type: :string, description: "The Anthropic environment identifier."},
             environment_key: %Schema{type: :string, description: "The Anthropic environment key. Never returned."},
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
        :anthropic_environment_id,
        :environment_key,
        :name,
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
        conn |> put_status(:bad_request) |> json(%{message: changeset_message(changeset)})
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
    operation_id: "listSandboxes",
    parameters: @account_parameters,
    responses:
      Map.put(
        @error_responses,
        :ok,
        {"Sandboxes", "application/json",
         %Schema{
           type: :object,
           properties: %{sandboxes: %Schema{type: :array, items: @sandbox_schema}},
           required: [:sandboxes]
         }}
      )
  )

  def index(%{assigns: %{selected_account: account}} = conn, _params) do
    json(conn, %{sandboxes: account |> Sandboxes.list_sandboxes() |> Enum.map(&serialize_sandbox/1)})
  end

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
    attrs = Map.take(body_params, [:template, :vcpus, :memory_mb, :workspace_gb])

    case Sandboxes.create_sandbox(account, attrs) do
      {:ok, sandbox} -> conn |> put_status(:created) |> json(serialize_sandbox(sandbox))
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

  def show(%{assigns: %{selected_account: account}, params: %{sandbox_id: sandbox_id}} = conn, _params) do
    with_sandbox(conn, account, sandbox_id, fn sandbox -> json(conn, serialize_sandbox(sandbox)) end)
  end

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

  def pause(%{assigns: %{selected_account: account}, params: %{sandbox_id: sandbox_id}} = conn, _params) do
    with_sandbox(conn, account, sandbox_id, fn sandbox ->
      case Sandboxes.pause(sandbox) do
        {:ok, sandbox} -> json(conn, serialize_sandbox(sandbox))
        {:error, reason} -> sandbox_error(conn, reason)
      end
    end)
  end

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

  def resume(%{assigns: %{selected_account: account}, params: %{sandbox_id: sandbox_id}} = conn, _params) do
    with_sandbox(conn, account, sandbox_id, fn sandbox ->
      case Sandboxes.resume(sandbox) do
        {:ok, sandbox} -> json(conn, serialize_sandbox(sandbox))
        {:error, reason} -> sandbox_error(conn, reason)
      end
    end)
  end

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

  def delete(%{assigns: %{selected_account: account}, params: %{sandbox_id: sandbox_id}} = conn, _params) do
    with_sandbox(conn, account, sandbox_id, fn sandbox ->
      case Sandboxes.delete(sandbox) do
        {:ok, _deleted} -> send_resp(conn, :no_content, "")
        {:error, reason} -> sandbox_error(conn, reason)
      end
    end)
  end

  defp with_sandbox(conn, account, sandbox_id, fun) do
    case Sandboxes.get_sandbox(account, sandbox_id) do
      {:ok, sandbox} -> fun.(sandbox)
      {:error, :not_found} -> not_found(conn, "Sandbox not found.")
    end
  end

  defp not_found(conn, message), do: conn |> put_status(:not_found) |> json(%{message: message})

  defp sandbox_error(conn, {:invalid_state, state}) do
    conn |> put_status(:conflict) |> json(%{message: "The sandbox is #{state}."})
  end

  defp sandbox_error(conn, :no_node) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{message: "No sandbox node with the template ready is connected."})
  end

  defp sandbox_error(conn, :not_connected) do
    conn |> put_status(:service_unavailable) |> json(%{message: "The sandbox's node is not connected."})
  end

  defp sandbox_error(conn, :node_disconnected) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{message: "The sandbox's node disconnected during the operation."})
  end

  defp sandbox_error(conn, :timeout) do
    conn |> put_status(:gateway_timeout) |> json(%{message: "The sandbox's node did not answer in time."})
  end

  defp sandbox_error(conn, %Ecto.Changeset{} = changeset) do
    conn |> put_status(:bad_request) |> json(%{message: changeset_message(changeset)})
  end

  defp sandbox_error(conn, reason) when is_binary(reason) do
    conn |> put_status(:bad_gateway) |> json(%{message: "The sandbox node rejected the operation: #{reason}"})
  end

  defp sandbox_error(conn, reason) do
    conn |> put_status(:internal_server_error) |> json(%{message: "Sandbox operation failed: #{inspect(reason)}"})
  end

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(", ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp serialize_agent_environment(%AgentEnvironment{} = agent_environment) do
    Map.take(agent_environment, [
      :id,
      :anthropic_environment_id,
      :name,
      :template,
      :vcpus,
      :memory_mb,
      :workspace_gb,
      :max_idle_seconds,
      :pause_grace_seconds,
      :enabled,
      :inserted_at,
      :updated_at
    ])
  end

  defp serialize_sandbox(%Sandbox{} = sandbox) do
    Map.take(sandbox, [
      :id,
      :state,
      :template,
      :template_tag,
      :vcpus,
      :memory_mb,
      :workspace_gb,
      :node_name,
      :hostname,
      :agent_environment_id,
      :anthropic_session_id,
      :residency_work_id,
      :last_active_at,
      :paused_at,
      :error_message,
      :inserted_at,
      :updated_at
    ])
  end
end
