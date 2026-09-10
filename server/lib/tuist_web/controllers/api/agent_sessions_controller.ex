defmodule TuistWeb.API.AgentSessionsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentSession
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication

  plug(TuistWeb.Plugs.LoaderPlug)

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  # Agent sessions spend the account's Anthropic budget and drive
  # sandboxes, so every action requires an account administrator.
  plug AuthorizationPlug, {:account, :account, :update}

  tags ["Sandboxes"]

  @agent_session_schema %Schema{
    title: "SandboxAgentSession",
    description: "A Managed Agents session Tuist started on one of the account's connected environments.",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: "uuid"},
      anthropic_session_id: %Schema{type: :string},
      anthropic_agent_id: %Schema{type: :string},
      agent_environment_id: %Schema{type: :integer},
      sandbox_id: %Schema{type: :string, format: "uuid", nullable: true},
      title: %Schema{type: :string, nullable: true},
      repository_url: %Schema{type: :string, nullable: true},
      repository_ref: %Schema{type: :string, nullable: true},
      model: %Schema{type: :string, nullable: true},
      budget_cents: %Schema{type: :integer, nullable: true},
      status: %Schema{
        type: :string,
        nullable: true,
        description: "The last session status the server saw (running, idle, terminated, archived)."
      },
      stop_reason: %Schema{
        type: :string,
        nullable: true,
        description: "The stop reason of the latest idle event the server saw."
      },
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"}
    },
    required: [
      :id,
      :anthropic_session_id,
      :anthropic_agent_id,
      :agent_environment_id,
      :sandbox_id,
      :title,
      :repository_url,
      :repository_ref,
      :model,
      :budget_cents,
      :status,
      :stop_reason,
      :inserted_at,
      :updated_at
    ]
  }

  @usage_schema %Schema{
    title: "SandboxAgentSessionUsage",
    type: :object,
    nullable: true,
    properties: %{
      input_tokens: %Schema{type: :integer, nullable: true},
      output_tokens: %Schema{type: :integer, nullable: true},
      cache_read_input_tokens: %Schema{type: :integer, nullable: true},
      active_seconds: %Schema{type: :number, nullable: true},
      list_cost: %Schema{
        type: :object,
        nullable: true,
        properties: %{
          amount: %Schema{type: :string, description: "Minor units of the currency as a decimal string."},
          currency: %Schema{type: :string}
        },
        required: [:amount, :currency]
      }
    }
  }

  @agent_session_detail_schema %Schema{
    title: "SandboxAgentSessionDetail",
    description: "An agent session with its live status, usage and the state of its sandbox.",
    type: :object,
    properties:
      Map.merge(@agent_session_schema.properties, %{
        usage: @usage_schema,
        sandbox_state: %Schema{type: :string, nullable: true}
      }),
    required: @agent_session_schema.required ++ [:usage, :sandbox_state]
  }

  @event_schema %Schema{
    title: "SandboxAgentSessionEvent",
    type: :object,
    properties: %{
      index: %Schema{type: :integer, description: "Position in the session's event list, oldest first."},
      type: %Schema{type: :string},
      at: %Schema{type: :string, format: "date-time", nullable: true},
      text: %Schema{type: :string, nullable: true, description: "Text of message and tool result events."},
      command: %Schema{type: :string, nullable: true, description: "The command of a bash tool use."},
      tool_name: %Schema{type: :string, nullable: true},
      stop_reason: %Schema{type: :string, nullable: true, description: "Set on session.status_idle events."}
    },
    required: [:index, :type, :at, :text, :command, :tool_name, :stop_reason]
  }

  @account_parameters [
    account_handle: [in: :path, type: :string, required: true, description: "The account handle."]
  ]

  @session_parameters @account_parameters ++
                        [
                          agent_session_id: [
                            in: :path,
                            type: :string,
                            required: true,
                            description: "The agent session id."
                          ]
                        ]

  @error_responses %{
    forbidden: {"Forbidden", "application/json", Error},
    too_many_requests: Responses.authorization_throttled()
  }

  @anthropic_error_responses %{
    bad_gateway: {"Anthropic rejected the request", "application/json", Error}
  }

  operation(:create,
    summary: "Start an agent session.",
    description:
      "Creates a Managed Agents session on the account's connected environment with the prompt as its first message. The environment must hold an Anthropic API key. The agent is created on first use with the environment's model and system prompt and reused afterwards.",
    operation_id: "createSandboxAgentSession",
    parameters: @account_parameters,
    request_body:
      {"Agent session params", "application/json",
       %Schema{
         title: "CreateSandboxAgentSession",
         type: :object,
         properties: %{
           prompt: %Schema{type: :string, minLength: 1, description: "The first user message of the session."},
           agent_environment_id: %Schema{
             type: :integer,
             description: "The agent environment to run on. Defaults to the account's single enabled environment."
           },
           title: %Schema{type: :string, maxLength: 255, nullable: true},
           repository_url: %Schema{
             type: :string,
             maxLength: 512,
             nullable: true,
             description: "HTTPS URL of a repository to clone under /workspace before the agent starts."
           },
           repository_ref: %Schema{
             type: :string,
             maxLength: 255,
             nullable: true,
             description: "Branch, tag or commit sha to check out."
           },
           model: %Schema{type: :string, nullable: true, description: "Overrides the environment's model."},
           budget_cents: %Schema{
             type: :integer,
             minimum: 1,
             nullable: true,
             description: "Hard list-cost ceiling for the session in USD cents."
           },
           agent_id: %Schema{
             type: :string,
             nullable: true,
             description: "An existing Anthropic agent to run instead of the one Tuist manages."
           }
         },
         required: [:prompt]
       }},
    responses:
      @error_responses
      |> Map.merge(@anthropic_error_responses)
      |> Map.merge(%{
        created: {"Agent session", "application/json", @agent_session_schema},
        bad_request: {"Invalid params or no usable agent environment", "application/json", Error}
      })
  )

  def create(%{assigns: %{selected_account: account}, body_params: body_params} = conn, _params) do
    attrs =
      Map.take(body_params, [
        :prompt,
        :agent_environment_id,
        :title,
        :repository_url,
        :repository_ref,
        :model,
        :budget_cents,
        :agent_id
      ])

    created_by_user_id =
      case Authentication.current_user(conn) do
        %{id: user_id} -> user_id
        _ -> nil
      end

    case Sandboxes.start_agent_session(account, attrs, created_by_user_id: created_by_user_id) do
      {:ok, agent_session} -> conn |> put_status(:created) |> json(serialize(agent_session))
      {:error, reason} -> agent_session_error(conn, reason)
    end
  end

  operation(:index,
    summary: "List the account's agent sessions.",
    operation_id: "listSandboxAgentSessions",
    parameters: @account_parameters,
    responses:
      Map.put(
        @error_responses,
        :ok,
        {"Agent sessions", "application/json",
         %Schema{
           type: :object,
           properties: %{agent_sessions: %Schema{type: :array, items: @agent_session_schema}},
           required: [:agent_sessions]
         }}
      )
  )

  def index(%{assigns: %{selected_account: account}} = conn, _params) do
    json(conn, %{agent_sessions: account |> Sandboxes.list_agent_sessions() |> Enum.map(&serialize/1)})
  end

  operation(:show,
    summary: "Get an agent session with its live status.",
    description: "Reads the session back from Anthropic and returns its status, usage and the state of its sandbox.",
    operation_id: "getSandboxAgentSession",
    parameters: @session_parameters,
    responses:
      @error_responses
      |> Map.merge(@anthropic_error_responses)
      |> Map.merge(%{
        ok: {"Agent session", "application/json", @agent_session_detail_schema},
        not_found: {"The agent session was not found", "application/json", Error}
      })
  )

  def show(%{assigns: %{selected_account: account}, params: %{agent_session_id: agent_session_id}} = conn, _params) do
    with_agent_session(conn, account, agent_session_id, fn agent_session ->
      case Sandboxes.refresh_agent_session(agent_session) do
        {:ok, %{session: agent_session, status: status, usage: usage, sandbox_state: sandbox_state}} ->
          json(conn, Map.merge(serialize(agent_session), %{status: status, usage: usage, sandbox_state: sandbox_state}))

        {:error, reason} ->
          agent_session_error(conn, reason)
      end
    end)
  end

  operation(:create_message,
    summary: "Send a message to an agent session.",
    operation_id: "sendSandboxAgentSessionMessage",
    parameters: @session_parameters,
    request_body:
      {"Message params", "application/json",
       %Schema{
         title: "SendSandboxAgentSessionMessage",
         type: :object,
         properties: %{text: %Schema{type: :string, minLength: 1}},
         required: [:text]
       }},
    responses:
      @error_responses
      |> Map.merge(@anthropic_error_responses)
      |> Map.merge(%{
        accepted: "The message was queued for the session",
        not_found: {"The agent session was not found", "application/json", Error}
      })
  )

  def create_message(
        %{assigns: %{selected_account: account}, params: %{agent_session_id: agent_session_id}} = conn,
        _params
      ) do
    with_agent_session(conn, account, agent_session_id, fn agent_session ->
      case Sandboxes.send_agent_session_message(agent_session, conn.body_params.text) do
        :ok -> send_resp(conn, :accepted, "")
        {:error, reason} -> agent_session_error(conn, reason)
      end
    end)
  end

  operation(:index_events,
    summary: "List an agent session's events.",
    description:
      "Returns the session's events flattened to text, commands and stop reasons, oldest first. Pass the previous answer's `next_after` as `after` to receive only newer events.",
    operation_id: "listSandboxAgentSessionEvents",
    parameters:
      @session_parameters ++
        [
          after: [
            in: :query,
            type: :integer,
            required: false,
            description: "Only return events with an index greater than this value."
          ]
        ],
    responses:
      @error_responses
      |> Map.merge(@anthropic_error_responses)
      |> Map.merge(%{
        ok:
          {"Agent session events", "application/json",
           %Schema{
             type: :object,
             properties: %{
               events: %Schema{type: :array, items: @event_schema},
               next_after: %Schema{type: :integer, description: "Pass as `after` on the next call."}
             },
             required: [:events, :next_after]
           }},
        not_found: {"The agent session was not found", "application/json", Error}
      })
  )

  def index_events(
        %{assigns: %{selected_account: account}, params: %{agent_session_id: agent_session_id} = params} = conn,
        _params
      ) do
    with_agent_session(conn, account, agent_session_id, fn agent_session ->
      case Sandboxes.list_agent_session_events(agent_session, after: Map.get(params, :after, -1)) do
        {:ok, %{events: events, next_after: next_after}} -> json(conn, %{events: events, next_after: next_after})
        {:error, reason} -> agent_session_error(conn, reason)
      end
    end)
  end

  operation(:archive,
    summary: "Archive an agent session.",
    operation_id: "archiveSandboxAgentSession",
    parameters: @session_parameters,
    responses:
      @error_responses
      |> Map.merge(@anthropic_error_responses)
      |> Map.merge(%{
        ok: {"Agent session", "application/json", @agent_session_schema},
        not_found: {"The agent session was not found", "application/json", Error}
      })
  )

  def archive(%{assigns: %{selected_account: account}, params: %{agent_session_id: agent_session_id}} = conn, _params) do
    with_agent_session(conn, account, agent_session_id, fn agent_session ->
      case Sandboxes.archive_agent_session(agent_session) do
        {:ok, agent_session} -> json(conn, serialize(agent_session))
        {:error, reason} -> agent_session_error(conn, reason)
      end
    end)
  end

  defp with_agent_session(conn, account, agent_session_id, fun) do
    case Sandboxes.get_agent_session(account, agent_session_id) do
      {:ok, agent_session} -> fun.(agent_session)
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{message: "Agent session not found."})
    end
  end

  defp agent_session_error(conn, %Ecto.Changeset{} = changeset) do
    conn |> put_status(:bad_request) |> json(%{message: changeset_message(changeset)})
  end

  defp agent_session_error(conn, :no_agent_environment) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      message:
        "No usable agent environment: pass agent_environment_id or connect exactly one enabled environment to the account."
    })
  end

  defp agent_session_error(conn, :missing_api_key) do
    conn
    |> put_status(:bad_request)
    |> json(%{message: "The agent environment has no Anthropic API key. Set one with PATCH on the agent environment."})
  end

  defp agent_session_error(conn, %{status: status, message: message}) do
    conn |> put_status(:bad_gateway) |> json(%{message: "Anthropic answered #{status}: #{message}"})
  end

  defp agent_session_error(conn, {:malformed_response, _body}) do
    conn |> put_status(:bad_gateway) |> json(%{message: "Anthropic answered with an unexpected body."})
  end

  defp agent_session_error(conn, reason) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{message: "Agent session operation failed: #{inspect(reason)}"})
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

  defp serialize(%AgentSession{} = agent_session) do
    agent_session
    |> Map.take([
      :id,
      :anthropic_session_id,
      :anthropic_agent_id,
      :agent_environment_id,
      :sandbox_id,
      :title,
      :repository_url,
      :repository_ref,
      :model,
      :budget_cents,
      :inserted_at,
      :updated_at
    ])
    |> Map.merge(%{status: agent_session.last_status, stop_reason: agent_session.last_stop_reason})
  end
end
