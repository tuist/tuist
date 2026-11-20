defmodule TuistWeb.API.BazelRemoteActionsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Bazel
  alias Tuist.RemoteExecution.Actions
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

  plug(TuistWeb.Plugs.CastAndValidate, json_render_error_v2: true, render_error: TuistWeb.RenderAPIErrorPlug)
  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  tags ["Bazel"]

  @path_params [
    account_handle: [in: :path, type: :string, required: true, description: "Account handle."],
    project_handle: [in: :path, type: :string, required: true, description: "Project handle."],
    invocation_id: [in: :path, type: :string, required: true, description: "Bazel invocation identifier."]
  ]
  @milliseconds %Schema{
    type: :number,
    nullable: true,
    description: "Milliseconds between the executor's reported timestamps. Null when the executor did not report them."
  }
  @summary_properties %{
    id: %Schema{type: :string, description: "The remote execution operation ID."},
    invocation_id: %Schema{type: :string},
    action_digest: %Schema{
      type: :object,
      description: "The REAPI Action digest.",
      properties: %{hash: %Schema{type: :string}, size_bytes: %Schema{type: :integer}},
      required: [:hash, :size_bytes]
    },
    mnemonic: %Schema{type: :string},
    target: %Schema{type: :string, description: "The Bazel target label, when the client reported it."},
    execution_path: %Schema{
      type: :string,
      enum: ["scheduled", "lease", ""],
      description: "Whether the action ran on a scheduled worker or a worker leased for the invocation."
    },
    memory_gb: %Schema{type: :integer},
    cached_result: %Schema{type: :boolean, description: "Whether the executor served a cached result."},
    status_code: %Schema{type: :integer, description: "The gRPC status code of the execution; 0 is OK."},
    exit_code: %Schema{type: :integer},
    queued_at: %Schema{type: :string, format: :"date-time", nullable: true},
    duration_ms: @milliseconds,
    queue_ms: @milliseconds,
    input_fetch_ms: @milliseconds,
    execution_ms: @milliseconds,
    output_upload_ms: @milliseconds
  }
  @pair %Schema{
    type: :object,
    properties: %{name: %Schema{type: :string}, value: %Schema{type: :string}},
    required: [:name, :value]
  }
  @summary %Schema{
    title: "BazelRemoteAction",
    type: :object,
    properties: @summary_properties,
    required: Map.keys(@summary_properties)
  }
  @detail_properties Map.merge(@summary_properties, %{
                       tool_name: %Schema{type: :string},
                       tool_version: %Schema{type: :string},
                       configuration_id: %Schema{type: :string},
                       worker: %Schema{type: :string},
                       sandbox_id: %Schema{type: :string},
                       timeout_ms: %Schema{type: :integer},
                       do_not_cache: %Schema{type: :boolean},
                       arguments: %Schema{type: :array, items: %Schema{type: :string}},
                       arguments_truncated: %Schema{type: :boolean},
                       environment: %Schema{
                         type: :array,
                         items: @pair,
                         description: "Values of variables whose names contain TOKEN, SECRET, PASSWORD or KEY are ****."
                       },
                       working_directory: %Schema{
                         type: :string,
                         description:
                           "Relative to the action's input root, which is /workspace/action on Tuist's workers. Empty for the input root itself."
                       },
                       platform: %Schema{type: :array, items: @pair},
                       output_paths: %Schema{
                         type: :array,
                         items: %Schema{type: :string},
                         description: "The declared outputs, up to 32 KiB of paths."
                       },
                       output_count: %Schema{
                         type: :integer,
                         description:
                           "How many outputs the command declared; more than output_paths when the list was cut."
                       },
                       status_message: %Schema{type: :string},
                       stdout: %Schema{type: :string, description: "Up to the first 16 KiB of standard output."},
                       stdout_size_bytes: %Schema{type: :integer},
                       stdout_truncated: %Schema{type: :boolean},
                       stderr: %Schema{type: :string, description: "Up to the first 16 KiB of standard error."},
                       stderr_size_bytes: %Schema{type: :integer},
                       stderr_truncated: %Schema{type: :boolean},
                       timestamps: %Schema{
                         type: :object,
                         description: "The executor's reported timestamps; null when not reported.",
                         additionalProperties: %Schema{type: :string, format: :"date-time", nullable: true}
                       },
                       errors: %Schema{
                         type: :array,
                         description:
                           "Compiler errors recognised in the recorded stderr of a failed action, in order. Empty when none were recognised.",
                         items: %Schema{
                           type: :object,
                           properties: %{
                             path: %Schema{type: :string},
                             line: %Schema{type: :integer},
                             column: %Schema{type: :integer, nullable: true},
                             message: %Schema{type: :string}
                           },
                           required: [:path, :line, :column, :message]
                         }
                       }
                     })
  @detail %Schema{
    title: "BazelRemoteActionDetail",
    type: :object,
    properties: @detail_properties,
    required: Map.keys(@detail_properties)
  }
  @errors %{
    not_found: {"Invocation or action not found", "application/json", Error},
    forbidden: {"Access denied", "application/json", Error}
  }

  operation(:index,
    summary: "List the remote actions of a Bazel invocation.",
    operation_id: "listBazelRemoteActions",
    description:
      "Actions Tuist remote execution ran for the invocation, as the execution gateway recorded them, kept for 90 days. Records are best effort: a missing action does not prove it did not run remotely.",
    parameters:
      @path_params ++
        [
          page_size: [
            in: :query,
            type: %Schema{type: :integer, default: 20, minimum: 1, maximum: 100},
            description: "The maximum number of results to return."
          ],
          page: [in: :query, type: %Schema{type: :integer, default: 1, minimum: 1}, description: "The page number."],
          sort_by: [
            in: :query,
            type: %Schema{type: :string, enum: ["duration", "queued_at"], default: "duration"},
            description: "Longest first, or earliest queued first."
          ],
          failed: [
            in: :query,
            type: :boolean,
            description: "Only actions that exited non-zero or whose execution failed."
          ],
          mnemonic: [in: :query, type: :string, description: "Only actions with this mnemonic."]
        ],
    responses:
      Map.put(
        @errors,
        :ok,
        {"Remote actions", "application/json",
         %Schema{
           title: "BazelRemoteActionsList",
           type: :object,
           properties: %{actions: %Schema{type: :array, items: @summary}, pagination_metadata: PaginationMetadata},
           required: [:actions, :pagination_metadata]
         }}
      )
  )

  def index(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    case Bazel.get_invocation(project.id, params.invocation_id, include_cache_summary: false) do
      {:ok, invocation} ->
        {actions, meta} =
          Actions.list(project.id, invocation.invocation_id, %{
            page: params[:page],
            page_size: params[:page_size],
            sort_by: params[:sort_by],
            failed: params[:failed] == true,
            mnemonic: params[:mnemonic]
          })

        json(conn, %{
          actions: Enum.map(actions, &Actions.summary_json/1),
          pagination_metadata: %{
            has_next_page: meta.has_next_page?,
            has_previous_page: meta.has_previous_page?,
            current_page: meta.current_page,
            page_size: meta.page_size,
            total_count: meta.total_count,
            total_pages: meta.total_pages
          }
        })

      {:error, :not_found} ->
        not_found(conn)
    end
  end

  operation(:show,
    summary: "Get one remote action of a Bazel invocation.",
    operation_id: "getBazelRemoteAction",
    description:
      "Returns the action's command, environment, platform, worker, exit code, the start of its standard output and error, output paths and phase timings.",
    parameters:
      @path_params ++
        [operation_id: [in: :path, type: :string, required: true, description: "The ID from listBazelRemoteActions."]],
    responses: Map.put(@errors, :ok, {"Remote action", "application/json", @detail})
  )

  def show(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    with {:ok, invocation} <- Bazel.get_invocation(project.id, params.invocation_id, include_cache_summary: false),
         {:ok, action} <- Actions.get(project.id, invocation.invocation_id, params.operation_id) do
      json(conn, Actions.json(action))
    else
      {:error, :not_found} -> not_found(conn)
    end
  end

  operation(:log,
    summary: "Read part of a remote action's standard output or error.",
    operation_id: "getBazelRemoteActionLog",
    description:
      "Returns up to 64 KiB of the stream, by byte offset in the original stream. Tuist records the first 16 KiB of each stream and copies longer ones whole, or their last 16 MiB when they are longer, kept like other run artifacts; `recorded` lists the byte ranges available. Without `offset`, returns the stream's last `limit` bytes.",
    parameters:
      @path_params ++
        [
          operation_id: [in: :path, type: :string, required: true, description: "The ID from listBazelRemoteActions."],
          stream: [in: :path, type: %Schema{type: :string, enum: ["stdout", "stderr"]}, required: true],
          offset: [in: :query, type: %Schema{type: :integer, minimum: 0}, description: "Byte offset to read from."],
          limit: [
            in: :query,
            type: %Schema{type: :integer, minimum: 1, maximum: 65_536, default: 65_536},
            description: "Bytes to read."
          ]
        ],
    responses:
      Map.put(
        @errors,
        :ok,
        {"Remote action log", "application/json",
         %Schema{
           title: "BazelRemoteActionLog",
           type: :object,
           properties: %{
             stream: %Schema{type: :string, enum: ["stdout", "stderr"]},
             size_bytes: %Schema{type: :integer, description: "The stream's size when the action ran."},
             offset: %Schema{type: :integer, description: "Where `text` starts in the stream."},
             text: %Schema{type: :string, description: "Empty when the range was not recorded."},
             recorded: %Schema{
               type: :array,
               description: "The stream's recorded byte ranges.",
               items: %Schema{
                 type: :object,
                 properties: %{offset: %Schema{type: :integer}, length: %Schema{type: :integer}},
                 required: [:offset, :length]
               }
             }
           },
           required: [:stream, :size_bytes, :offset, :text, :recorded]
         }}
      )
  )

  def log(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    with {:ok, invocation} <- Bazel.get_invocation(project.id, params.invocation_id, include_cache_summary: false),
         {:ok, action} <- Actions.get(project.id, invocation.invocation_id, params.operation_id) do
      stored = Actions.stored_logs(project.account, project, action)
      json(conn, Actions.log_range(action, params.stream, stored[params.stream], params[:offset], params[:limit]))
    else
      {:error, :not_found} -> not_found(conn)
    end
  end

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{message: "Remote action not found."})
end
