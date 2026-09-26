defmodule TuistWeb.API.MixController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Mix
  alias Tuist.VCS.RemoteURL
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags ["Mix"]

  operation(:create_build,
    summary: "Create a Mix (Elixir) compile build.",
    operation_id: "createMixBuild",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the account."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project."
      ]
    ],
    request_body:
      {"Mix build data", "application/json",
       %Schema{
         type: :object,
         properties: %{
           id: %Schema{
             type: :string,
             format: :uuid,
             description: "Client-generated UUID for the build."
           },
           contract_version: %Schema{
             type: :string,
             description: "Version of the client-server analytics contract the caller was built against."
           },
           duration_ms: %Schema{
             type: :integer,
             minimum: 0,
             description: "Total compile duration in milliseconds."
           },
           started_at: %Schema{
             type: :string,
             format: :"date-time",
             description: "ISO 8601 timestamp for when the compile started."
           },
           status: %Schema{
             type: :string,
             enum: ["success", "failure"],
             description: "The outcome of the compile."
           },
           is_ci: %Schema{
             type: :boolean,
             description: "Whether the compile ran on a continuous integration provider."
           },
           elixir_version: %Schema{
             type: :string,
             description: "The Elixir version used to compile (e.g., \"1.20.2\")."
           },
           otp_version: %Schema{
             type: :string,
             description: "The Erlang/OTP release used to compile (e.g., \"29\")."
           },
           mix_env: %Schema{
             type: :string,
             description: ~s{The Mix environment the compile ran in (e.g., "dev", "test").}
           },
           git_branch: %Schema{type: :string, description: "Git branch."},
           git_commit_sha: %Schema{type: :string, description: "Git commit SHA."},
           git_ref: %Schema{type: :string, description: "Git ref."},
           git_remote_url_origin: %Schema{type: :string, description: "Git remote URL origin."},
           ci_run_id: %Schema{type: :string, description: "The CI run identifier."},
           ci_project_handle: %Schema{
             type: :string,
             description: "The CI project handle (e.g., 'owner/repo')."
           },
           ci_provider: %Schema{
             type: :string,
             enum: ["github", "gitlab", "bitrise", "circleci", "buildkite", "codemagic"],
             description: "The CI provider."
           },
           ci_host: %Schema{
             type: :string,
             description: "The CI host URL, useful for self-hosted providers."
           },
           machine_metrics: %Schema{
             type: :array,
             description: "Machine performance samples collected during the compile.",
             items: %Schema{
               type: :object,
               properties: %{
                 timestamp: %Schema{type: :number, description: "Unix timestamp in seconds."},
                 cpu_usage_percent: %Schema{
                   type: :number,
                   description: "CPU usage percentage (0-100)."
                 },
                 memory_used_bytes: %Schema{type: :integer},
                 memory_total_bytes: %Schema{type: :integer},
                 network_bytes_in: %Schema{type: :integer},
                 network_bytes_out: %Schema{type: :integer},
                 disk_bytes_read: %Schema{type: :integer},
                 disk_bytes_written: %Schema{type: :integer}
               },
               required: [:timestamp, :cpu_usage_percent, :memory_used_bytes, :memory_total_bytes]
             }
           },
           custom_metadata: %Schema{
             type: :object,
             description: "Custom metadata for the build run.",
             properties: %{
               tags: %Schema{
                 type: :array,
                 items: %Schema{type: :string, maxLength: 50, pattern: "^[a-zA-Z0-9_-]+$"},
                 maxItems: 50
               },
               values: %Schema{
                 type: :object,
                 additionalProperties: %Schema{type: :string, maxLength: 500},
                 maxProperties: 20
               }
             }
           },
           diagnostics: %Schema{
             type: :array,
             description: "Compile-time diagnostics emitted during the build.",
             items: %Schema{
               type: :object,
               properties: %{
                 severity: %Schema{type: :string, enum: ["warning", "error"]},
                 file: %Schema{type: :string, description: "Path relative to the project root."},
                 module: %Schema{type: :string, description: "The module the diagnostic belongs to."},
                 message: %Schema{type: :string, description: "The diagnostic message."},
                 line: %Schema{type: :integer, nullable: true, minimum: 0},
                 column: %Schema{type: :integer, nullable: true, minimum: 0},
                 compiler: %Schema{
                   type: :string,
                   description: ~s{The compiler that emitted it (e.g. "elixir", "app").}
                 }
               },
               required: [:severity, :message]
             }
           }
         },
         required: [:id, :duration_ms, :status]
       }},
    responses: %{
      created:
        {"Build created", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid, description: "The build ID."}
           },
           required: [:id]
         }},
      bad_request: {"Invalid request", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def create_build(%{assigns: %{selected_project: project}, body_params: body} = conn, _params) do
    body = RemoteURL.strip_credentials_from_params(body)

    case Mix.create_build(build_attributes(conn, project, body)) do
      {:ok, build_id} ->
        conn
        |> put_status(:created)
        |> json(%{id: build_id})

      {:error, _reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "The custom metadata is invalid."})
    end
  end

  defp build_attributes(conn, project, body) do
    metadata = body[:custom_metadata] || %{}

    %{
      id: body[:id],
      project_id: project.id,
      account_id: TuistWeb.Authentication.authenticated_subject_account(conn).id,
      duration_ms: body[:duration_ms],
      started_at: body[:started_at],
      status: body[:status],
      is_ci: body[:is_ci] || false,
      elixir_version: body[:elixir_version],
      otp_version: body[:otp_version],
      mix_env: body[:mix_env],
      git_branch: body[:git_branch],
      git_commit_sha: body[:git_commit_sha],
      git_ref: body[:git_ref],
      git_remote_url_origin: body[:git_remote_url_origin],
      ci_provider: body[:ci_provider],
      ci_run_id: body[:ci_run_id],
      ci_project_handle: body[:ci_project_handle],
      ci_host: body[:ci_host],
      contract_version: body[:contract_version],
      custom_tags: Map.get(metadata, :tags, []),
      custom_values: Map.get(metadata, :values, %{}),
      diagnostics: body[:diagnostics] || [],
      machine_metrics: body[:machine_metrics] || []
    }
  end
end
