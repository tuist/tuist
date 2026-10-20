defmodule TuistWeb.API.MixController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Mix
  alias Tuist.Mix.Query
  alias Tuist.Projects
  alias Tuist.VCS.RemoteURL
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.MixBuild
  alias TuistWeb.Authentication
  alias TuistWeb.Plugs.ReportPublishingPlug

  plug(ReportPublishingPlug, {:preflight, :mix} when action == :create_build)

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.ReportActorPlug when action == :create_build)
  plug(ReportPublishingPlug, :mix when action == :create_build)
  plug(TuistWeb.Plugs.LoaderPlug when action != :create_build)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build when action != :create_build)

  tags ["Mix"]

  # The same limits the context enforces, so a report that would be truncated
  # or wrapped by a storage column is refused instead.
  @limits Mix.limits()
  @uint32 @limits.uint32
  @int64 @limits.int64
  @max_name 1_024
  @max_message 10_000

  operation(:create_build,
    summary: "Create a Mix (Elixir) compile build.",
    operation_id: "createMixBuild",
    parameters: [
      "x-tuist-actor-id": TuistWeb.API.Schemas.ReportActor.header(),
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
             maximum: @uint32,
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
             maxItems: @limits.machine_metrics,
             description: "Machine performance samples collected during the compile.",
             items: %Schema{
               type: :object,
               properties: %{
                 timestamp: %Schema{
                   type: :number,
                   minimum: 0,
                   maximum: @limits.timestamp,
                   description: "Unix timestamp in seconds."
                 },
                 cpu_usage_percent: %Schema{
                   type: :number,
                   minimum: 0,
                   maximum: 100,
                   description: "CPU usage percentage (0-100)."
                 },
                 memory_used_bytes: %Schema{type: :integer, minimum: 0, maximum: @int64},
                 memory_total_bytes: %Schema{type: :integer, minimum: 0, maximum: @int64},
                 network_bytes_in: %Schema{type: :integer, minimum: 0, maximum: @int64},
                 network_bytes_out: %Schema{type: :integer, minimum: 0, maximum: @int64},
                 disk_bytes_read: %Schema{type: :integer, minimum: 0, maximum: @int64},
                 disk_bytes_written: %Schema{type: :integer, minimum: 0, maximum: @int64}
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
           files: %Schema{
             type: :array,
             maxItems: @limits.files,
             description:
               "Per-file compile profile: how long each file compiled, the project files it depends on, and how long it sat paused while other files compiled.",
             items: %Schema{
               type: :object,
               properties: %{
                 path: %Schema{type: :string, maxLength: @max_name, description: "Path relative to the project root."},
                 start_offset_ms: %Schema{
                   type: :integer,
                   nullable: true,
                   minimum: 0,
                   maximum: @uint32,
                   description: "Milliseconds from the start of the compile to when the file started compiling."
                 },
                 compile_duration_ms: %Schema{type: :integer, minimum: 0, maximum: @uint32},
                 wait_duration_ms: %Schema{type: :integer, minimum: 0, maximum: @uint32},
                 modules: %Schema{
                   type: :array,
                   maxItems: @limits.nested,
                   items: %Schema{type: :string, maxLength: @max_name}
                 },
                 dependencies: %Schema{
                   type: :array,
                   maxItems: @limits.nested,
                   description: "The project files this file references.",
                   items: %Schema{
                     type: :object,
                     properties: %{
                       path: %Schema{
                         type: :string,
                         maxLength: @max_name,
                         description: "Path relative to the project root."
                       },
                       kind: %Schema{
                         type: :string,
                         enum: ["compile", "export", "runtime"],
                         description:
                           "compile: needed while the file compiles. export: its struct or an import. runtime: only called from inside functions."
                       }
                     },
                     required: [:path, :kind]
                   }
                 },
                 waits: %Schema{
                   type: :array,
                   maxItems: @limits.nested,
                   items: %Schema{
                     type: :object,
                     properties: %{
                       module: %Schema{type: :string, description: "The module the file waited on."},
                       path: %Schema{
                         type: :string,
                         nullable: true,
                         description: "The project file defining that module, when known."
                       },
                       kind: %Schema{type: :string, description: "What was needed, such as module or struct."},
                       duration_ms: %Schema{type: :integer, minimum: 0, maximum: @uint32},
                       start_offset_ms: %Schema{
                         type: :integer,
                         nullable: true,
                         minimum: 0,
                         maximum: @uint32,
                         description: "Milliseconds from the start of the compile to when the wait began, when known."
                       }
                     },
                     required: [:module, :duration_ms]
                   }
                 }
               },
               required: [:path, :compile_duration_ms]
             }
           },
           steps: %Schema{
             type: :array,
             maxItems: @limits.steps,
             description:
               "The work of the build besides compiling files, such as type checking a module or writing modules to disk.",
             items: %Schema{
               type: :object,
               properties: %{
                 category: %Schema{
                   type: :string,
                   enum: ["type_check", "write", "compiler", "other"],
                   description: "The kind of work."
                 },
                 title: %Schema{type: :string, maxLength: @max_name, description: "What the step did."},
                 path: %Schema{
                   type: :string,
                   nullable: true,
                   description: "The project file the step is about, when it concerns one."
                 },
                 start_offset_ms: %Schema{
                   type: :integer,
                   minimum: 0,
                   maximum: @uint32,
                   description: "Milliseconds from the start of the compile to when the step started."
                 },
                 duration_ms: %Schema{type: :integer, minimum: 0, maximum: @uint32}
               },
               required: [:category, :title, :start_offset_ms, :duration_ms]
             }
           },
           dependency_cache: %Schema{
             type: :array,
             maxItems: 5_000,
             description: "Dependency-cache lookups and bypasses. An omitted array means no caching data was reported.",
             items: %Schema{
               type: :object,
               properties: %{
                 dependency: %Schema{type: :string, minLength: 1, maxLength: @max_name},
                 outcome: %Schema{type: :string, enum: ["local_hit", "remote_hit", "miss", "bypass"]},
                 reason: %Schema{
                   type: :string,
                   enum: [
                     "",
                     "not_enabled",
                     "local_dependency",
                     "custom_compiler",
                     "unmodeled_input",
                     "inputs_changed",
                     "store_failed"
                   ]
                 },
                 key: %Schema{type: :string, pattern: "^([a-f0-9]{64})?$"},
                 duration_ms: %Schema{type: :integer, minimum: 0, maximum: @uint32},
                 read_bytes: %Schema{
                   type: :integer,
                   nullable: true,
                   minimum: 0,
                   maximum: @int64,
                   description:
                     "Successful read bytes. Remote CAS payload bytes or local artifact and manifest copy bytes, identified by read_source."
                 },
                 write_bytes: %Schema{
                   type: :integer,
                   nullable: true,
                   minimum: 0,
                   maximum: @int64,
                   description:
                     "Successful write bytes. Remote CAS payload bytes or local artifact and manifest copy bytes, identified by write_source."
                 },
                 read_duration_us: %Schema{
                   type: :integer,
                   nullable: true,
                   minimum: 0,
                   maximum: @int64,
                   description:
                     "Successful client transfer or local restore duration in microseconds. Local restores include verification and installation; remote transfers exclude installation."
                 },
                 write_duration_us: %Schema{
                   type: :integer,
                   nullable: true,
                   minimum: 0,
                   maximum: @int64,
                   description:
                     "Successful client transfer or local publication duration in microseconds. Local publications include snapshot verification. Excludes compilation."
                 },
                 read_source: %Schema{
                   type: :string,
                   nullable: true,
                   enum: ["local", "remote"],
                   description: "Read measurement provenance; legacy observations may omit it."
                 },
                 write_source: %Schema{
                   type: :string,
                   nullable: true,
                   enum: ["local", "remote"],
                   description: "Write measurement provenance; legacy observations may omit it."
                 },
                 saved_duration_ms: %Schema{
                   type: :integer,
                   nullable: true,
                   minimum: 0,
                   maximum: @uint32,
                   description:
                     "Estimated compilation time avoided on a hit, from the original compilation. Not elapsed build time saved."
                 }
               },
               required: [:dependency, :outcome, :duration_ms]
             }
           },
           diagnostics: %Schema{
             type: :array,
             maxItems: @limits.diagnostics,
             description: "Compile-time diagnostics emitted during the build.",
             items: %Schema{
               type: :object,
               properties: %{
                 severity: %Schema{type: :string, enum: ["warning", "error"]},
                 file: %Schema{type: :string, maxLength: @max_name, description: "Path relative to the project root."},
                 module: %Schema{
                   type: :string,
                   maxLength: @max_name,
                   description: "The module the diagnostic belongs to."
                 },
                 message: %Schema{type: :string, maxLength: @max_message, description: "The diagnostic message."},
                 line: %Schema{type: :integer, nullable: true, minimum: 0, maximum: @uint32},
                 column: %Schema{type: :integer, nullable: true, minimum: 0, maximum: @uint32},
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
    body = conn |> ReportPublishingPlug.parameters(body) |> RemoteURL.strip_credentials_from_params()

    case Mix.create_build(build_attributes(conn, project, body)) do
      {:ok, build_id} ->
        if !ReportPublishingPlug.network_publisher?(conn),
          do: Projects.notify_connected(project, Authentication.current_user(conn))

        conn
        |> put_status(:created)
        |> json(%{id: build_id})

      {:error, :invalid_dependency_cache} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "The dependency cache data is invalid."})

      {:error, _reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "The custom metadata is invalid."})
    end
  end

  defp publisher_id(conn) do
    case Authentication.authenticated_subject_account(conn) do
      nil -> 0
      account -> account.id
    end
  end

  @build_fields ~w(id duration_ms started_at status elixir_version otp_version mix_env
                   git_branch git_commit_sha git_ref git_remote_url_origin ci_provider
                   ci_run_id ci_project_handle ci_host contract_version)a

  defp build_attributes(conn, project, body) do
    metadata = body[:custom_metadata] || %{}

    body
    |> Map.take(@build_fields)
    |> Map.merge(%{
      project_id: project.id,
      account_id: publisher_id(conn),
      is_ci: body[:is_ci] || false,
      custom_tags: Map.get(metadata, :tags, []),
      custom_values: Map.get(metadata, :values, %{}),
      diagnostics: body[:diagnostics] || [],
      files: body[:files] || [],
      steps: body[:steps] || [],
      machine_metrics: body[:machine_metrics] || [],
      dependency_cache: body[:dependency_cache] || []
    })
    |> Map.merge(Tuist.ReportActor.attributes(conn))
  end

  operation(:list_builds,
    summary: "List Mix (Elixir) builds for a project, newest first.",
    operation_id: "listMixBuilds",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."],
      git_branch: [in: :query, type: :string, description: "Filter by git branch."],
      status: [
        in: :query,
        type: %Schema{title: "MixBuildStatus", type: :string, enum: ["success", "failure"]},
        description: "Filter by build status."
      ],
      is_ci: [in: :query, type: :boolean, description: "Filter by whether the build ran on CI."],
      mix_env: [in: :query, type: :string, description: "Filter by Mix environment, for example dev or test."],
      page_size: [
        in: :query,
        type: %Schema{
          title: "MixBuildsIndexPageSize",
          description: "The maximum number of builds to return in a single page.",
          type: :integer,
          default: 20,
          minimum: 1,
          maximum: 100
        }
      ],
      page: [
        in: :query,
        type: %Schema{
          title: "MixBuildsIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok: {"List of Mix builds", "application/json", MixBuild.list()},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def list_builds(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    json(conn, Query.list_builds(project.id, Map.new(params, fn {key, value} -> {to_string(key), value} end)))
  end

  operation(:get_build,
    summary: "Get a Mix (Elixir) build with its diagnostics counts and dependency cache summary.",
    operation_id: "getMixBuild",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."],
      build_id: [in: :path, type: :string, required: true, description: "The build ID."]
    ],
    responses: %{
      ok: {"Mix build details", "application/json", MixBuild.detail()},
      not_found: {"Build not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def get_build(%{assigns: %{selected_project: project}, params: %{build_id: build_id}} = conn, _params) do
    case Query.get_build(project.id, build_id) do
      {:ok, build} -> json(conn, build)
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{message: "Build not found."})
    end
  end
end
