defmodule TuistWeb.API.BuildsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Builds
  alias Tuist.Builds.CASOutput
  alias Tuist.Storage
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadCompletion
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadPart
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadParts
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadUrl
  alias TuistWeb.API.Schemas.ArtifactUploadId
  alias TuistWeb.API.Schemas.Builds.Build
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata
  alias TuistWeb.Authentication

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags ["Builds"]

  operation(:index,
    summary: "List builds associated with a given project.",
    operation_id: "listBuilds",
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
      ],
      status: [
        in: :query,
        type: %Schema{
          title: "BuildStatus",
          type: :string,
          enum: ["success", "failure"]
        },
        description: "Filter by build status."
      ],
      category: [
        in: :query,
        type: %Schema{
          title: "BuildCategory",
          type: :string,
          enum: ["clean", "incremental"]
        },
        description: "Filter by build category."
      ],
      scheme: [
        in: :query,
        type: :string,
        description: "Filter by scheme name."
      ],
      configuration: [
        in: :query,
        type: :string,
        description: "Filter by configuration name."
      ],
      git_branch: [
        in: :query,
        type: :string,
        description: "Filter by git branch."
      ],
      tags: [
        in: :query,
        type: %Schema{type: :array, items: %Schema{type: :string}},
        style: :form,
        explode: true,
        description: "Filter by tags. Returns builds containing ALL specified tags."
      ],
      values: [
        in: :query,
        type: %Schema{type: :array, items: %Schema{type: :string}},
        style: :form,
        explode: true,
        description:
          "Filter by custom values (key:value format). Returns builds matching ALL specified values. Example: ticket:PROJ-1234"
      ],
      page_size: [
        in: :query,
        type: %Schema{
          title: "BuildsIndexPageSize",
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
          title: "BuildsIndexPage",
          description: "The page number to return.",
          type: :integer,
          default: 1,
          minimum: 1
        }
      ]
    ],
    responses: %{
      ok:
        {"List of builds", "application/json",
         %Schema{
           type: :object,
           properties: %{
             builds: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid, description: "The build ID."},
                   duration: %Schema{type: :integer, description: "Build duration in milliseconds."},
                   status: %Schema{
                     type: :string,
                     enum: ["success", "failure", "processing", "failed_processing"],
                     description: "Build status."
                   },
                   category: %Schema{
                     type: :string,
                     enum: ["clean", "incremental"],
                     nullable: true,
                     description: "Build category."
                   },
                   scheme: %Schema{type: :string, nullable: true, description: "The scheme that was built."},
                   configuration: %Schema{type: :string, nullable: true, description: "The configuration used."},
                   xcode_version: %Schema{type: :string, nullable: true, description: "Xcode version."},
                   macos_version: %Schema{type: :string, nullable: true, description: "macOS version."},
                   model_identifier: %Schema{type: :string, nullable: true, description: "Machine model identifier."},
                   is_ci: %Schema{type: :boolean, description: "Whether the build ran on CI."},
                   git_branch: %Schema{type: :string, nullable: true, description: "Git branch."},
                   git_commit_sha: %Schema{type: :string, nullable: true, description: "Git commit SHA."},
                   git_ref: %Schema{type: :string, nullable: true, description: "Git ref."},
                   cacheable_tasks_count: %Schema{type: :integer, description: "Total cacheable tasks."},
                   cacheable_task_local_hits_count: %Schema{type: :integer, description: "Local cache hits."},
                   cacheable_task_remote_hits_count: %Schema{type: :integer, description: "Remote cache hits."},
                   inserted_at: %Schema{type: :string, format: :"date-time", description: "When the build was created."},
                   url: %Schema{type: :string, description: "URL to view the build in the dashboard."},
                   custom_metadata: %Schema{
                     type: :object,
                     description: "Custom metadata for the build run.",
                     properties: %{
                       tags: %Schema{type: :array, items: %Schema{type: :string}},
                       values: %Schema{type: :object, additionalProperties: %Schema{type: :string}}
                     }
                   },
                   ran_by: %Schema{
                     type: :object,
                     nullable: true,
                     description: "The account that triggered the build.",
                     properties: %{
                       handle: %Schema{type: :string, description: "The handle of the account."}
                     }
                   }
                 },
                 required: [
                   :id,
                   :duration,
                   :status,
                   :is_ci,
                   :cacheable_tasks_count,
                   :cacheable_task_local_hits_count,
                   :cacheable_task_remote_hits_count,
                   :inserted_at,
                   :url
                 ]
               }
             },
             pagination_metadata: PaginationMetadata
           },
           required: [:builds, :pagination_metadata]
         }},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def index(
        %{assigns: %{selected_project: selected_project}, params: %{page_size: page_size, page: page} = params} = conn,
        _params
      ) do
    filters = build_filters(selected_project.id, params)
    custom_values = parse_values_param(Map.get(params, :values))

    attrs = %{
      filters: filters,
      order_by: [:inserted_at],
      order_directions: [:desc],
      page: page,
      page_size: page_size
    }

    {builds, meta} = Builds.list_build_runs(attrs, preload: [:ran_by_account], custom_values: custom_values)

    json(conn, %{
      builds:
        Enum.map(builds, fn build ->
          %{
            id: build.id,
            duration: build.duration,
            status: build.status,
            category: if(build.category != "", do: build.category),
            scheme: build.scheme,
            configuration: build.configuration,
            xcode_version: build.xcode_version,
            macos_version: build.macos_version,
            model_identifier: build.model_identifier,
            is_ci: build.is_ci,
            git_branch: build.git_branch,
            git_commit_sha: build.git_commit_sha,
            git_ref: build.git_ref,
            cacheable_tasks_count: build.cacheable_tasks_count,
            cacheable_task_local_hits_count: build.cacheable_task_local_hits_count,
            cacheable_task_remote_hits_count: build.cacheable_task_remote_hits_count,
            inserted_at: build.inserted_at,
            url: ~p"/#{selected_project.account.name}/#{selected_project.name}/builds/build-runs/#{build.id}",
            custom_metadata: %{
              tags: build.custom_tags || [],
              values: build.custom_values || %{}
            },
            ran_by:
              if(Ecto.assoc_loaded?(build.ran_by_account) and build.ran_by_account,
                do: %{handle: build.ran_by_account.name}
              )
          }
        end),
      pagination_metadata: %{
        has_next_page: meta.has_next_page?,
        has_previous_page: meta.has_previous_page?,
        current_page: meta.current_page,
        page_size: meta.page_size,
        total_count: meta.total_count,
        total_pages: meta.total_pages
      }
    })
  end

  operation(:show,
    summary: "Get a build by ID.",
    operation_id: "getBuild",
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
      ],
      build_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The ID of the build."
      ]
    ],
    responses: %{
      ok:
        {"Build details", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid, description: "The build ID."},
             duration: %Schema{type: :integer, description: "Build duration in milliseconds."},
             status: %Schema{
               type: :string,
               enum: ["success", "failure", "processing", "failed_processing"],
               description: "Build status."
             },
             category: %Schema{
               type: :string,
               enum: ["clean", "incremental"],
               nullable: true,
               description: "Build category."
             },
             scheme: %Schema{type: :string, nullable: true, description: "The scheme that was built."},
             configuration: %Schema{type: :string, nullable: true, description: "The configuration used."},
             xcode_version: %Schema{type: :string, nullable: true, description: "Xcode version."},
             macos_version: %Schema{type: :string, nullable: true, description: "macOS version."},
             model_identifier: %Schema{type: :string, nullable: true, description: "Machine model identifier."},
             is_ci: %Schema{type: :boolean, description: "Whether the build ran on CI."},
             git_branch: %Schema{type: :string, nullable: true, description: "Git branch."},
             git_commit_sha: %Schema{type: :string, nullable: true, description: "Git commit SHA."},
             git_ref: %Schema{type: :string, nullable: true, description: "Git ref."},
             cacheable_tasks_count: %Schema{type: :integer, description: "Total cacheable tasks."},
             cacheable_task_local_hits_count: %Schema{type: :integer, description: "Local cache hits."},
             cacheable_task_remote_hits_count: %Schema{type: :integer, description: "Remote cache hits."},
             inserted_at: %Schema{type: :string, format: :"date-time", description: "When the build was created."},
             url: %Schema{type: :string, description: "URL to view the build in the dashboard."},
             custom_metadata: %Schema{
               type: :object,
               description: "Custom metadata for the build run.",
               properties: %{
                 tags: %Schema{type: :array, items: %Schema{type: :string}},
                 values: %Schema{type: :object, additionalProperties: %Schema{type: :string}}
               }
             }
           },
           required: [
             :id,
             :duration,
             :status,
             :is_ci,
             :cacheable_tasks_count,
             :cacheable_task_local_hits_count,
             :cacheable_task_remote_hits_count,
             :inserted_at,
             :url
           ]
         }},
      not_found: {"Build not found", "application/json", Error},
      forbidden: {"You don't have permission to access this resource", "application/json", Error}
    }
  )

  def show(%{assigns: %{selected_project: selected_project}, params: %{build_id: build_id}} = conn, _params) do
    case Builds.get_build(build_id) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Build not found."})

      {:ok, build} ->
        if build.project_id == selected_project.id do
          json(conn, %{
            id: build.id,
            duration: build.duration,
            status: build.status,
            category: if(build.category != "", do: build.category),
            scheme: build.scheme,
            configuration: build.configuration,
            xcode_version: build.xcode_version,
            macos_version: build.macos_version,
            model_identifier: build.model_identifier,
            is_ci: build.is_ci,
            git_branch: build.git_branch,
            git_commit_sha: build.git_commit_sha,
            git_ref: build.git_ref,
            cacheable_tasks_count: build.cacheable_tasks_count,
            cacheable_task_local_hits_count: build.cacheable_task_local_hits_count,
            cacheable_task_remote_hits_count: build.cacheable_task_remote_hits_count,
            inserted_at: build.inserted_at,
            url: ~p"/#{selected_project.account.name}/#{selected_project.name}/builds/build-runs/#{build.id}",
            custom_metadata: %{
              tags: build.custom_tags || [],
              values: build.custom_values || %{}
            }
          })
        else
          conn
          |> put_status(:not_found)
          |> json(%{message: "Build not found."})
        end
    end
  end

  defp build_filters(project_id, params) do
    filters = [%{field: :project_id, op: :==, value: project_id}]

    filters =
      if Map.get(params, :status) do
        filters ++ [%{field: :status, op: :==, value: params.status}]
      else
        filters
      end

    filters =
      if Map.get(params, :category) do
        filters ++ [%{field: :category, op: :==, value: params.category}]
      else
        filters
      end

    filters =
      if Map.get(params, :scheme) do
        filters ++ [%{field: :scheme, op: :==, value: params.scheme}]
      else
        filters
      end

    filters =
      if Map.get(params, :configuration) do
        filters ++ [%{field: :configuration, op: :==, value: params.configuration}]
      else
        filters
      end

    filters =
      if Map.get(params, :git_branch) do
        filters ++ [%{field: :git_branch, op: :==, value: params.git_branch}]
      else
        filters
      end

    case Map.get(params, :tags) do
      nil ->
        filters

      [] ->
        filters

      tags ->
        tag_filters = Enum.map(tags, fn tag -> %{field: :custom_tags, op: :contains, value: tag} end)
        filters ++ tag_filters
    end
  end

  defp parse_values_param(nil), do: nil
  defp parse_values_param([]), do: nil

  defp parse_values_param(values_list) do
    values_list
    |> Enum.map(fn pair ->
      case String.split(pair, ":", parts: 2) do
        [key, value] -> {String.trim(key), String.trim(value)}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  operation(:create,
    summary: "Create a new build.",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project's account."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project to create a build for."
      ]
    ],
    operation_id: "createBuild",
    request_body:
      {"Build params", "application/json",
       %Schema{
         title: "BuildParams",
         description: "Parameters to create a single build.",
         type: :object,
         properties: %{
           id: %Schema{
             description: "UUID of a build generated by the system.",
             type: :string
           },
           duration: %Schema{
             description: "Duration of the build in milliseconds.",
             type: :integer
           },
           macos_version: %Schema{
             type: :string,
             description: "The version of macOS used during the build."
           },
           xcode_version: %Schema{
             type: :string,
             description: "The version of Xcode used during the build."
           },
           is_ci: %Schema{
             type: :boolean,
             description: "Indicates if the build was executed on a Continuous Integration (CI) system."
           },
           model_identifier: %Schema{
             type: :string,
             description: "Identifier for the model where the build was executed, such as MacBookAir10,1."
           },
           scheme: %Schema{
             type: :string,
             description: "The scheme used for the build."
           },
           configuration: %Schema{
             type: :string,
             description: "The build configuration (e.g., Debug, Release)."
           },
           status: %Schema{
             type: :string,
             description: "The status of the build run.",
             enum: ["success", "failure", "processing"]
           },
           category: %Schema{
             type: :string,
             description: "The category of the build run, can be clean or incremental.",
             enum: ["clean", "incremental"]
           },
           git_commit_sha: %Schema{
             type: :string,
             description: "The commit SHA."
           },
           git_branch: %Schema{
             type: :string,
             description: "The git branch."
           },
           git_ref: %Schema{
             type: :string,
             description: "The git reference."
           },
           git_remote_url_origin: %Schema{
             type: :string,
             description: "The git remote URL origin."
           },
           ci_run_id: %Schema{
             type: :string,
             description: "The CI run identifier (e.g., GitHub Actions run ID, GitLab pipeline ID)."
           },
           ci_project_handle: %Schema{
             type: :string,
             description: "The CI project handle (e.g., 'owner/repo' for GitHub, project path for GitLab)."
           },
           ci_host: %Schema{
             type: :string,
             description: "The CI host URL (optional, for self-hosted instances)."
           },
           ci_provider: %Schema{
             type: :string,
             description: "The CI provider.",
             enum: ["github", "gitlab", "bitrise", "circleci", "buildkite", "codemagic"]
           },
           issues: %Schema{
             type: :array,
             description: "The build issues associated with the build run.",
             items: %Schema{
               type: :object,
               properties: %{
                 type: %Schema{
                   type: :string,
                   description: "The type of the issue.",
                   enum: [:warning, :error]
                 },
                 target: %Schema{
                   type: :string,
                   description: "The target name associated with the issue."
                 },
                 project: %Schema{
                   type: :string,
                   description: "The project name associated with the issue."
                 },
                 title: %Schema{
                   type: :string,
                   description: "The title of the build issue."
                 },
                 signature: %Schema{
                   type: :string,
                   description: "The signature of the issue."
                 },
                 step_type: %Schema{
                   type: :string,
                   description: "The step type where the issue occurred, such as swift_compilation.",
                   enum: [
                     :c_compilation,
                     :swift_compilation,
                     :script_execution,
                     :create_static_library,
                     :linker,
                     :copy_swift_libs,
                     :compile_assets_catalog,
                     :compile_storyboard,
                     :write_auxiliary_file,
                     :link_storyboards,
                     :copy_resource_file,
                     :merge_swift_module,
                     :xib_compilation,
                     :swift_aggregated_compilation,
                     :precompile_bridging_header,
                     :other,
                     :validate_embedded_binary,
                     :validate
                   ]
                 },
                 path: %Schema{
                   type: :string,
                   description: "The file path where the issue occurred, relative to the project root."
                 },
                 message: %Schema{
                   type: :string,
                   description: "The detailed message of the issue."
                 },
                 starting_line: %Schema{
                   type: :integer,
                   description: "The starting line number of the issue."
                 },
                 ending_line: %Schema{
                   type: :integer,
                   description: "The ending line number of the issue."
                 },
                 starting_column: %Schema{
                   type: :integer,
                   description: "The starting column number of the issue."
                 },
                 ending_column: %Schema{
                   type: :integer,
                   description: "The ending column number of the issue."
                 }
               },
               required: [
                 :type,
                 :target,
                 :project,
                 :title,
                 :signature,
                 :step_type,
                 :starting_line,
                 :ending_line,
                 :starting_column,
                 :ending_column
               ]
             }
           },
           files: %Schema{
             type: :array,
             description: "Compiled files associated with the build run.",
             items: %Schema{
               type: :object,
               properties: %{
                 type: %Schema{
                   type: :string,
                   description: "The type of the file.",
                   enum: [:swift, :c]
                 },
                 target: %Schema{
                   type: :string,
                   description: "The target name associated with the file."
                 },
                 project: %Schema{
                   type: :string,
                   description: "The project name associated with the file."
                 },
                 path: %Schema{
                   type: :string,
                   description: "The file path where the issue occurred, relative to the project root."
                 },
                 compilation_duration: %Schema{
                   type: :integer,
                   description: "The duration of the compilation for the file in milliseconds."
                 }
               },
               required: [
                 :type,
                 :target,
                 :project,
                 :path,
                 :compilation_duration
               ]
             }
           },
           targets: %Schema{
             type: :array,
             description: "Targets with build metadata associated with the build run.",
             items: %Schema{
               type: :object,
               properties: %{
                 name: %Schema{
                   type: :string,
                   description: "The target name."
                 },
                 project: %Schema{
                   type: :string,
                   description: "The target's project name."
                 },
                 build_duration: %Schema{
                   type: :integer,
                   description: "The build duration for the target in milliseconds."
                 },
                 compilation_duration: %Schema{
                   type: :integer,
                   description: "The duration of the compilation for the target in milliseconds."
                 },
                 status: %Schema{
                   type: :string,
                   description: "The status of the target's build.",
                   enum: ["success", "failure"]
                 }
               },
               required: [
                 :name,
                 :project,
                 :build_duration,
                 :compilation_duration,
                 :status
               ]
             }
           },
           cacheable_tasks: %Schema{
             type: :array,
             description: "Cacheable tasks associated with the build run.",
             items: %Schema{
               type: :object,
               properties: %{
                 type: %Schema{
                   type: :string,
                   description: "The type of cacheable task.",
                   enum: [:clang, :swift]
                 },
                 status: %Schema{
                   type: :string,
                   description: "The cache status of the task.",
                   enum: [:hit_local, :hit_remote, :miss]
                 },
                 key: %Schema{
                   type: :string,
                   description: "The cache key of the task."
                 },
                 read_duration: %Schema{
                   type: :number,
                   description: "The duration in milliseconds for reading from cache."
                 },
                 write_duration: %Schema{
                   type: :number,
                   description: "The duration in milliseconds for writing to cache."
                 },
                 description: %Schema{
                   type: :string,
                   description: "Optional description of the cacheable task."
                 },
                 cas_output_node_ids: %Schema{
                   type: :array,
                   description: "Array of CAS output node IDs associated with this cacheable task.",
                   items: %Schema{type: :string}
                 }
               },
               required: [:type, :status, :key]
             }
           },
           cas_outputs: %Schema{
             type: :array,
             description: "CAS output operations associated with the build run.",
             items: %Schema{
               type: :object,
               properties: %{
                 node_id: %Schema{
                   type: :string,
                   description: "The CAS node identifier."
                 },
                 checksum: %Schema{
                   type: :string,
                   description: "The checksum of the CAS object."
                 },
                 size: %Schema{
                   type: :integer,
                   description: "The size of the CAS object in bytes."
                 },
                 duration: %Schema{
                   type: :number,
                   description: "The duration of the CAS operation in milliseconds."
                 },
                 compressed_size: %Schema{
                   type: :integer,
                   description: "The compressed size of the CAS object in bytes."
                 },
                 operation: %Schema{
                   type: :string,
                   description: "The type of CAS operation.",
                   enum: [:download, :upload]
                 },
                 type: %Schema{
                   type: :string,
                   description: "The type of the CAS output file.",
                   enum: Enum.map(CASOutput.valid_types(), &String.to_atom/1)
                 }
               },
               required: [:node_id, :checksum, :size, :duration, :compressed_size, :operation]
             }
           },
           xcode_cache_upload_enabled: %Schema{
             type: :boolean,
             description: "Whether Xcode cache upload was enabled for this build."
           },
           custom_metadata: %Schema{
             type: :object,
             description: "Custom metadata for the build run.",
             properties: %{
               tags: %Schema{
                 type: :array,
                 items: %Schema{type: :string, maxLength: 50, pattern: "^[a-zA-Z0-9_-]+$"},
                 maxItems: 10,
                 description: "Simple string labels for filtering/grouping (e.g., 'nightly', 'release')."
               },
               values: %Schema{
                 type: :object,
                 additionalProperties: %Schema{type: :string, maxLength: 500},
                 description: "Key-value pairs for structured data. URL values will auto-link in the UI."
               }
             }
           },
           machine_metrics: %Schema{
             type: :array,
             description: "Machine performance metrics collected during the build.",
             items: %Schema{
               type: :object,
               properties: %{
                 timestamp: %Schema{type: :number, description: "Unix timestamp in seconds."},
                 cpu_usage_percent: %Schema{type: :number, description: "CPU usage percentage (0-100)."},
                 memory_used_bytes: %Schema{type: :integer, description: "Memory used in bytes."},
                 memory_total_bytes: %Schema{type: :integer, description: "Total memory in bytes."},
                 network_bytes_in: %Schema{type: :integer, description: "Network bytes received per second."},
                 network_bytes_out: %Schema{type: :integer, description: "Network bytes sent per second."},
                 disk_bytes_read: %Schema{type: :integer, description: "Disk bytes read per second."},
                 disk_bytes_written: %Schema{type: :integer, description: "Disk bytes written per second."}
               },
               required: [
                 :timestamp,
                 :cpu_usage_percent,
                 :memory_used_bytes,
                 :memory_total_bytes,
                 :network_bytes_in,
                 :network_bytes_out,
                 :disk_bytes_read,
                 :disk_bytes_written
               ]
             }
           }
         },
         required: [
           :id,
           :is_ci
         ]
       }},
    responses: %{
      ok: {
        "The created build",
        "application/json",
        Build
      },
      unauthorized: {"You need to be authenticated to create a build", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      bad_request: {"The request parameters are invalid", "application/json", Error}
    }
  )

  def create(%{assigns: %{selected_project: selected_project}, body_params: body_params} = conn, _params) do
    account = Authentication.authenticated_subject_account(conn)

    run_params =
      body_params
      |> Map.put(:project, selected_project)
      |> Map.put(:account, account)

    {:ok, build} = get_or_create_build(run_params)

    if build.status not in ["processing", "failed_processing"] do
      Tuist.VCS.enqueue_vcs_pull_request_comment(%{
        git_commit_sha: build.git_commit_sha,
        git_ref: build.git_ref,
        git_remote_url_origin: Map.get(body_params, :git_remote_url_origin),
        project_id: selected_project.id
      })
    end

    conn
    |> put_status(:ok)
    |> json(%{
      type: "build",
      id: build.id,
      status: build.status,
      duration: build.duration,
      project_id: build.project_id,
      url: url(~p"/#{selected_project.account.name}/#{selected_project.name}/builds/build-runs/#{build.id}")
    })
  end

  defp get_or_create_build(params) do
    case Builds.get_build(params.id) do
      {:ok, build} ->
        {:ok, build}

      {:error, :not_found} ->
        custom_metadata = Map.get(params, :custom_metadata, %{})

        build_attrs = %{
          id: params.id,
          duration: Map.get(params, :duration, 0),
          macos_version: Map.get(params, :macos_version),
          xcode_version: Map.get(params, :xcode_version),
          is_ci: Map.get(params, :is_ci),
          model_identifier: Map.get(params, :model_identifier),
          scheme: Map.get(params, :scheme),
          configuration: Map.get(params, :configuration),
          project_id: params.project.id,
          account_id: params.account.id,
          status: Map.get(params, :status, "success"),
          category: Map.get(params, :category),
          git_branch: Map.get(params, :git_branch),
          git_commit_sha: Map.get(params, :git_commit_sha),
          git_ref: Map.get(params, :git_ref),
          ci_run_id: Map.get(params, :ci_run_id),
          ci_project_handle: Map.get(params, :ci_project_handle),
          ci_host: Map.get(params, :ci_host),
          ci_provider: Map.get(params, :ci_provider),
          issues: Map.get(params, :issues, []),
          files: Map.get(params, :files, []),
          targets: Map.get(params, :targets, []),
          cacheable_tasks: Map.get(params, :cacheable_tasks, []),
          cas_outputs: Map.get(params, :cas_outputs, []),
          xcode_cache_upload_enabled: Map.get(params, :xcode_cache_upload_enabled, false),
          custom_tags: Map.get(custom_metadata, :tags, []),
          custom_values: Map.get(custom_metadata, :values, %{}),
          machine_metrics: Map.get(params, :machine_metrics, [])
        }

        {:ok, build} = build_attrs |> Builds.create_build() |> handle_build_creation_result(params.id)

        if build.status == "processing" do
          storage_key = Builds.build_storage_key(params.project.account.name, params.project.name, params.id)

          %{
            build_id: build.id,
            storage_key: storage_key,
            account_id: params.account.id,
            project_id: params.project.id,
            xcode_cache_upload_enabled: Map.get(params, :xcode_cache_upload_enabled, false),
            build_metadata: %{
              macos_version: Map.get(params, :macos_version),
              xcode_version: Map.get(params, :xcode_version),
              is_ci: Map.get(params, :is_ci),
              model_identifier: Map.get(params, :model_identifier),
              scheme: Map.get(params, :scheme),
              configuration: Map.get(params, :configuration),
              git_branch: Map.get(params, :git_branch),
              git_commit_sha: Map.get(params, :git_commit_sha),
              git_ref: Map.get(params, :git_ref),
              ci_run_id: Map.get(params, :ci_run_id),
              ci_project_handle: Map.get(params, :ci_project_handle),
              ci_host: Map.get(params, :ci_host),
              ci_provider: Map.get(params, :ci_provider),
              git_remote_url_origin: Map.get(params, :git_remote_url_origin),
              custom_tags: Map.get(custom_metadata, :tags, []),
              custom_values: Map.get(custom_metadata, :values, %{})
            },
            vcs_comment_params: %{
              git_commit_sha: Map.get(params, :git_commit_sha),
              git_ref: Map.get(params, :git_ref),
              git_remote_url_origin: Map.get(params, :git_remote_url_origin),
              project_id: params.project.id
            }
          }
          |> Tuist.Builds.Workers.ProcessBuildWorker.new()
          |> Oban.insert!()
        end

        {:ok, build}
    end
  end

  defp handle_build_creation_result({:ok, build}, _build_id), do: {:ok, build}

  defp handle_build_creation_result({:error, changeset}, build_id) do
    if Keyword.has_key?(changeset.errors, :id) do
      case Builds.get_build(build_id) do
        {:ok, build} -> {:ok, build}
        {:error, :not_found} -> {:error, :creation_failed}
      end
    else
      {:error, changeset}
    end
  end

  operation(:multipart_start,
    summary: "Start a multipart upload for a build archive.",
    description:
      "Initiates a multipart upload for a build archive (zip containing the xcactivitylog, CAS metadata, and machine metrics) to be processed server-side.",
    operation_id: "startBuildsMultipartUpload",
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
      {"Build multipart upload start params", "application/json",
       %Schema{
         title: "BuildMultipartUploadStartParams",
         description: "Parameters to start a multipart upload for a build archive.",
         type: :object,
         properties: %{
           build_id: %Schema{
             type: :string,
             format: :uuid,
             description: "The build ID."
           }
         },
         required: [:build_id]
       }},
    responses: %{
      ok: {"The multipart upload has been started", "application/json", ArtifactUploadId},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error}
    }
  )

  def multipart_start(
        %{assigns: %{selected_project: selected_project}, body_params: %{build_id: build_id}} = conn,
        _params
      ) do
    account = Authentication.authenticated_subject_account(conn)
    object_key = Builds.build_storage_key(selected_project.account.name, selected_project.name, build_id)

    multipart_upload_id = Storage.multipart_start(object_key, account)

    json(conn, %{status: "success", data: %{upload_id: multipart_upload_id}})
  end

  operation(:multipart_generate_url,
    summary: "Generate a signed URL for uploading a build archive part.",
    description:
      "Given an upload ID and a part number, this endpoint returns a signed URL that can be used to upload a part of the build archive (zip containing the xcactivitylog, CAS metadata, and machine metrics).",
    operation_id: "generateBuildsMultipartUploadURL",
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
      {"Build multipart upload URL generation params", "application/json",
       %Schema{
         title: "BuildMultipartUploadURLGenerationParams",
         description: "Parameters to generate a signed URL for a build multipart upload part.",
         type: :object,
         properties: %{
           build_id: %Schema{
             type: :string,
             format: :uuid,
             description: "The build ID."
           },
           multipart_upload_part: ArtifactMultipartUploadPart
         },
         required: [:build_id, :multipart_upload_part]
       }},
    responses: %{
      ok: {"The URL has been generated", "application/json", ArtifactMultipartUploadUrl},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error}
    }
  )

  def multipart_generate_url(
        %{
          assigns: %{selected_project: selected_project},
          body_params: %{
            build_id: build_id,
            multipart_upload_part: %{part_number: part_number, upload_id: multipart_upload_id} = multipart_upload_part
          }
        } = conn,
        _params
      ) do
    content_length = Map.get(multipart_upload_part, :content_length)
    object_key = Builds.build_storage_key(selected_project.account.name, selected_project.name, build_id)

    url =
      Storage.multipart_generate_url(
        object_key,
        multipart_upload_id,
        part_number,
        selected_project.account,
        expires_in: 120,
        content_length: content_length
      )

    json(conn, %{status: "success", data: %{url: url}})
  end

  operation(:multipart_complete,
    summary: "Complete a multipart upload for a build archive.",
    description:
      "Given the upload ID and all the parts with their ETags, this endpoint completes the multipart upload of the build archive and enqueues it for server-side processing.",
    operation_id: "completeBuildsMultipartUpload",
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
      {"Build multipart upload completion params", "application/json",
       %Schema{
         title: "BuildMultipartUploadCompletionParams",
         description: "Parameters to complete a multipart upload for a build.",
         type: :object,
         properties: %{
           build_id: %Schema{
             type: :string,
             format: :uuid,
             description: "The build ID."
           },
           multipart_upload_parts: ArtifactMultipartUploadParts
         },
         required: [:build_id, :multipart_upload_parts]
       }},
    responses: %{
      ok: {"The upload has been completed", "application/json", ArtifactMultipartUploadCompletion},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error}
    }
  )

  def multipart_complete(
        %{
          assigns: %{selected_project: selected_project},
          body_params: %{
            build_id: build_id,
            multipart_upload_parts: %ArtifactMultipartUploadParts{parts: parts, upload_id: multipart_upload_id}
          }
        } = conn,
        _params
      ) do
    object_key = Builds.build_storage_key(selected_project.account.name, selected_project.name, build_id)

    :ok =
      Storage.multipart_complete_upload(
        object_key,
        multipart_upload_id,
        Enum.map(parts, fn %{part_number: part_number, etag: etag} ->
          {part_number, etag}
        end),
        selected_project.account
      )

    json(conn, %{status: "success", data: %{}})
  end
end
