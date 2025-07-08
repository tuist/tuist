defmodule TuistWeb.API.AnalyticsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.CommandEvents
  alias Tuist.Storage
  alias Tuist.VCS
  alias Tuist.Xcode
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadPart
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadParts
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadUrl
  alias TuistWeb.API.Schemas.ArtifactUploadId
  alias TuistWeb.API.Schemas.CommandEvent
  alias TuistWeb.API.Schemas.CommandEventArtifact
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :run)
  plug :bad_request_when_project_authenticated_from_non_ci_environment when action in [:create]

  tags ["Analytics"]

  operation(:create,
    summary: "Create a a new command analytics event",
    operation_id: "createCommandEvent",
    parameters: [
      project_id: [
        in: :query,
        type: :string,
        required: true,
        description: "The project id."
      ]
    ],
    request_body:
      {"Command event params", "application/json",
       %Schema{
         type: :object,
         properties: %{
           name: %Schema{
             type: :string,
             description: "The name of the command."
           },
           subcommand: %Schema{
             type: :string,
             description: "The subcommand of the command."
           },
           command_arguments: %Schema{
             type: :array,
             description: "The arguments of the command.",
             items: %Schema{
               type: :string
             }
           },
           client_id: %Schema{
             type: :string,
             description: "The client id of the command."
           },
           duration: %Schema{
             type: :integer,
             description: "The duration of the command."
           },
           tuist_version: %Schema{
             type: :string,
             description: "The version of Tuist that ran the command."
           },
           swift_version: %Schema{
             type: :string,
             description: "The version of Swift that ran the command."
           },
           macos_version: %Schema{
             type: :string,
             description: "The version of macOS that ran the command."
           },
           ran_at: %Schema{
             type: :string,
             format: :string,
             description: "The date for when the command was run."
           },
           params: %Schema{
             deprecated: true,
             type: :object,
             description: "Extra parameters.",
             properties: %{
               cacheable_targets: %Schema{
                 type: :array,
                 description: "A list of cacheable targets.",
                 items: %Schema{
                   type: :string
                 }
               },
               local_cache_target_hits: %Schema{
                 type: :array,
                 description: "A list of local cache target hits.",
                 items: %Schema{
                   type: :string
                 }
               },
               remote_cache_target_hits: %Schema{
                 type: :array,
                 description: "A list of remote cache target hits.",
                 items: %Schema{
                   type: :string
                 }
               },
               test_targets: %Schema{
                 type: :array,
                 description: "The list of targets that were tested.",
                 items: %Schema{
                   type: :string
                 }
               },
               local_test_target_hits: %Schema{
                 type: :array,
                 description: "A list of local targets whose tests were skipped.",
                 items: %Schema{
                   type: :string
                 }
               },
               remote_test_target_hits: %Schema{
                 type: :array,
                 description: "A list of remote targets whose tests were skipped.",
                 items: %Schema{
                   type: :string
                 }
               }
             }
           },
           is_ci: %Schema{
             type: :boolean,
             description: "Whether the command was run in a CI environment."
           },
           status: %Schema{
             type: :string,
             description: "The status of the command.",
             enum: [:success, :failure]
           },
           error_message: %Schema{
             type: :string,
             description: "The error message of the command."
           },
           git_commit_sha: %Schema{
             type: :string,
             description: "The commit SHA."
           },
           git_ref: %Schema{
             type: :string,
             description:
               "The git ref. When on CI, the value can be equal to remote reference such as `refs/pull/1234/merge`."
           },
           git_remote_url_origin: %Schema{
             type: :string,
             description: "The git remote URL origin."
           },
           git_branch: %Schema{
             type: :string,
             description: "The git branch."
           },
           preview_id: %Schema{
             type: :string,
             description: "The preview identifier."
           },
           build_run_id: %Schema{
             type: :string,
             description: "The build run identifier."
           },
           xcode_graph: %Schema{
             type: :object,
             description: "The schema for the Xcode graph.",
             required: [:name, :projects],
             properties: %{
               name: %Schema{
                 type: :string,
                 description: "Name of the Xcode graph"
               },
               binary_build_duration: %Schema{
                 type: :integer,
                 description:
                   "The estimated time in milliseconds that would take to build the part of the graph that has been replaced as binaries."
               },
               projects: %Schema{
                 type: :array,
                 description: "Projects present in an Xcode graph",
                 items: %Schema{
                   required: [:name, :path, :targets],
                   properties: %{
                     name: %Schema{
                       type: :string,
                       description: "Name of the project"
                     },
                     path: %Schema{
                       type: :string,
                       description: "Path of the project"
                     },
                     targets: %Schema{
                       type: :array,
                       description: "Targets present in a project",
                       items: %Schema{
                         type: :object,
                         required: [:name],
                         properties: %{
                           name: %Schema{
                             type: :string,
                             description: "Name of the target"
                           },
                           binary_cache_metadata: %Schema{
                             type: :object,
                             description: "Binary cache metadata",
                             required: [:hash, :hit],
                             properties: %{
                               hash: %Schema{
                                 type: :string,
                                 description: "Hash of the target"
                               },
                               hit: %Schema{
                                 type: :string,
                                 description: "The binary cache hit status",
                                 enum: ["miss", "local", "remote"]
                               },
                               build_duration: %Schema{
                                 type: :integer,
                                 description: "The compilation time of a binary in milliseconds."
                               }
                             }
                           },
                           selective_testing_metadata: %Schema{
                             type: :object,
                             description: "Selective testing metadata",
                             required: [:hash, :hit],
                             properties: %{
                               hash: %Schema{
                                 type: :string,
                                 description: "Hash of the target"
                               },
                               hit: %Schema{
                                 type: :string,
                                 description: "The selective testing hit status",
                                 enum: ["miss", "local", "remote"]
                               }
                             }
                           }
                         }
                       }
                     }
                   }
                 }
               }
             }
           }
         },
         required: [
           :name,
           :duration,
           :tuist_version,
           :swift_version,
           :macos_version,
           :is_ci,
           :client_id
         ]
       }},
    responses: %{
      ok: {"The command event was created", "application/json", CommandEvent},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"You don't have permission to create command events for the project.", "application/json", Error}
    }
  )

  def create(%{body_params: body_params, assigns: %{selected_project: selected_project}} = conn, _params) do
    current_user = Authentication.current_user(conn)

    user_id =
      if is_nil(current_user) do
        nil
      else
        current_user.id
      end

    git_commit_sha = Map.get(body_params, :git_commit_sha)
    git_ref = Map.get(body_params, :git_ref)
    git_remote_url_origin = Map.get(body_params, :git_remote_url_origin)
    preview_id = Map.get(body_params, :preview_id)
    build_run_id = Map.get(body_params, :build_run_id)

    cache_metadata = cache_metadata(body_params)
    selective_testing_metadata = selective_testing_metadata(body_params)

    command_event =
      CommandEvents.create_command_event(%{
        name: body_params.name,
        subcommand: Map.get(body_params, :subcommand, nil),
        command_arguments: body_params.command_arguments,
        duration: body_params.duration,
        tuist_version: body_params.tuist_version,
        swift_version: body_params.swift_version,
        macos_version: body_params.macos_version,
        cacheable_targets: cache_metadata.cacheable_targets,
        local_cache_target_hits: cache_metadata.local_cache_target_hits,
        remote_cache_target_hits: cache_metadata.remote_cache_target_hits,
        test_targets: selective_testing_metadata.test_targets,
        local_test_target_hits: selective_testing_metadata.local_test_target_hits,
        remote_test_target_hits: selective_testing_metadata.remote_test_target_hits,
        is_ci: body_params.is_ci,
        user_id: user_id,
        client_id: body_params.client_id,
        project_id: selected_project.id,
        status: Map.get(body_params, :status),
        error_message: Map.get(body_params, :error_message),
        preview_id: preview_id,
        git_commit_sha: git_commit_sha,
        git_ref: git_ref,
        git_remote_url_origin: git_remote_url_origin,
        git_branch: Map.get(body_params, :git_branch),
        ran_at: date(body_params),
        build_run_id: build_run_id
      })

    xcode_graph = Map.get(body_params, :xcode_graph)

    if not is_nil(xcode_graph) do
      Xcode.create_xcode_graph(%{command_event: command_event, xcode_graph: xcode_graph})
    end

    if Enum.member?(["test", "share", "bundle"], body_params.name) do
      VCS.enqueue_vcs_pull_request_comment(%{
        build_id: build_run_id,
        git_commit_sha: git_commit_sha,
        git_ref: git_ref,
        git_remote_url_origin: git_remote_url_origin,
        project_id: selected_project.id,
        preview_url_template: "#{url(~p"/")}:account_name/:project_name/previews/:preview_id",
        preview_qr_code_url_template: "#{url(~p"/")}:account_name/:project_name/previews/:preview_id/qr-code.png",
        command_run_url_template: "#{url(~p"/")}:account_name/:project_name/runs/:command_event_id",
        bundle_url_template: "#{url(~p"/")}:account_name/:project_name/bundles/:bundle_id",
        build_url_template: "#{url(~p"/")}:account_name/:project_name/builds/build-runs/:build_id"
      })
    end

    url =
      if is_nil(build_run_id) do
        url(~p"/#{selected_project.account.name}/#{selected_project.name}/runs/#{command_event.id}")
      else
        url(
          ~p"/#{selected_project.account.name}/#{selected_project.name}/builds/build-runs/#{String.downcase(build_run_id)}"
        )
      end

    conn
    |> put_status(:ok)
    |> json(%{
      id: command_event.id,
      project_id: command_event.project_id,
      name: command_event.name,
      url: url
    })
  end

  defp cache_metadata(params) do
    xcode_graph = Map.get(params, :xcode_graph)

    if is_nil(xcode_graph) do
      params = Map.get(params, :params, %{})

      %{
        cacheable_targets: Map.get(params, :cacheable_targets, []),
        local_cache_target_hits: Map.get(params, :local_cache_target_hits, []),
        remote_cache_target_hits: Map.get(params, :remote_cache_target_hits, [])
      }
    else
      targets = Enum.flat_map(xcode_graph.projects, & &1["targets"])

      %{
        cacheable_targets:
          targets
          |> Enum.filter(&(not is_nil(&1["binary_cache_metadata"]["hash"])))
          |> Enum.map(& &1["name"]),
        local_cache_target_hits:
          targets
          |> Enum.filter(&(&1["binary_cache_metadata"]["hit"] == "local"))
          |> Enum.map(& &1["name"]),
        remote_cache_target_hits:
          targets
          |> Enum.filter(&(&1["binary_cache_metadata"]["hit"] == "remote"))
          |> Enum.map(& &1["name"])
      }
    end
  end

  defp selective_testing_metadata(params) do
    xcode_graph = Map.get(params, :xcode_graph)

    if is_nil(xcode_graph) do
      params = Map.get(params, :params, %{})

      %{
        test_targets: Map.get(params, :test_targets, []),
        local_test_target_hits: Map.get(params, :local_test_target_hits, []),
        remote_test_target_hits: Map.get(params, :remote_test_target_hits, [])
      }
    else
      targets = Enum.flat_map(xcode_graph.projects, & &1["targets"])

      %{
        test_targets:
          targets
          |> Enum.filter(&(not is_nil(&1["selective_testing_metadata"]["hash"])))
          |> Enum.map(& &1["name"]),
        local_test_target_hits:
          targets
          |> Enum.filter(&(&1["selective_testing_metadata"]["hit"] == "local"))
          |> Enum.map(& &1["name"]),
        remote_test_target_hits:
          targets
          |> Enum.filter(&(&1["selective_testing_metadata"]["hit"] == "remote"))
          |> Enum.map(& &1["name"])
      }
    end
  end

  # CommandEvent artifacts

  operation(:multipart_start,
    summary: "It initiates a multipart upload for a command event artifact.",
    description:
      "The endpoint returns an upload ID that can be used to generate URLs for the individual parts and complete the upload.",
    operation_id: "startAnalyticsArtifactMultipartUpload",
    parameters: [
      run_id: [
        in: :path,
        type: :integer,
        required: true,
        description: "The id of the command event."
      ]
    ],
    request_body: {"Artifact to upload", "application/json", CommandEventArtifact},
    responses: %{
      ok: {"The upload has been started", "application/json", ArtifactUploadId},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The command event doesn't exist", "application/json", Error}
    }
  )

  defp date(body_params) do
    case Map.get(body_params, :ran_at) do
      nil ->
        DateTime.utc_now()

      date_string ->
        case DateTime.from_iso8601(date_string) do
          {:ok, date, _} -> date
          {:error, _} -> DateTime.utc_now()
        end
    end
  end

  def multipart_start(
        %{path_params: %{"run_id" => run_id}, body_params: %{type: type} = command_event_artifact} = conn,
        _params
      ) do
    with {:ok, object_key} <- get_object_key(%{type: type, run_id: run_id, name: command_event_artifact.name}) do
      upload_id = Storage.multipart_start(object_key)
      json(conn, %{status: "success", data: %{upload_id: upload_id}})
    end
  end

  operation(:multipart_generate_url,
    summary: "It generates a signed URL for uploading a part.",
    description:
      "Given an upload ID and a part number, this endpoint returns a signed URL that can be used to upload a part of a multipart upload. The URL is short-lived and expires in 120 seconds.",
    operation_id: "generateAnalyticsArtifactMultipartUploadURL",
    parameters: [
      run_id: [
        in: :path,
        type: :integer,
        required: true,
        description: "The id of the command event."
      ]
    ],
    request_body:
      {"Artifact to generate a signed URL for", "application/json",
       %Schema{
         type: :object,
         properties: %{
           command_event_artifact: CommandEventArtifact,
           multipart_upload_part: ArtifactMultipartUploadPart
         },
         required: [:command_event_artifact, :multipart_upload_part]
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
          path_params: %{"run_id" => run_id},
          body_params: %{
            command_event_artifact: %{type: type} = command_event_artifact,
            multipart_upload_part: %{part_number: part_number, upload_id: upload_id} = multipart_upload_part
          }
        } = conn,
        _params
      ) do
    with {:ok, object_key} <- get_object_key(%{type: type, run_id: run_id, name: command_event_artifact.name}) do
      expires_in = 120
      content_length = Map.get(multipart_upload_part, :content_length)

      url =
        Storage.multipart_generate_url(
          object_key,
          upload_id,
          part_number,
          expires_in: expires_in,
          content_length: content_length
        )

      json(conn, %{status: "success", data: %{url: url}})
    end
  end

  operation(:multipart_complete,
    summary: "It completes a multi-part upload.",
    description: "Given the upload ID and all the parts with their ETags, this endpoint completes the multipart upload.",
    operation_id: "completeAnalyticsArtifactMultipartUpload",
    parameters: [
      run_id: [
        in: :path,
        type: :integer,
        required: true,
        description: "The id of the command event."
      ]
    ],
    request_body:
      {"Command event artifact multipart upload completion", "application/json",
       %Schema{
         type: :object,
         properties: %{
           command_event_artifact: CommandEventArtifact,
           multipart_upload_parts: ArtifactMultipartUploadParts
         },
         required: [:command_event_artifact, :multipart_upload_parts]
       }},
    responses: %{
      no_content: "The upload has been completed",
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      internal_server_error: {"An internal server error occurred", "application/json", Error}
    }
  )

  def multipart_complete(
        %{
          path_params: %{"run_id" => run_id},
          body_params: %{
            command_event_artifact: %{type: type} = command_event_artifact,
            multipart_upload_parts: %ArtifactMultipartUploadParts{parts: parts, upload_id: upload_id}
          }
        } = conn,
        _params
      ) do
    with {:ok, object_key} <- get_object_key(%{type: type, run_id: run_id, name: command_event_artifact.name}) do
      :ok =
        Storage.multipart_complete_upload(
          object_key,
          upload_id,
          Enum.map(parts, fn %{part_number: part_number, etag: etag} ->
            {part_number, etag}
          end)
        )

      conn
      |> put_status(:no_content)
      |> json(%{})
    end
  end

  operation(:complete_artifacts_uploads,
    summary: "Completes artifacts uploads for a given command event",
    description:
      "Given a command event, it marks all artifact uploads as finished and does extra processing of a given command run, such as test flakiness detection.",
    operation_id: "completeAnalyticsArtifactsUploads",
    parameters: [
      run_id: [
        in: :path,
        type: :integer,
        required: true,
        description: "The id of the command event."
      ]
    ],
    request_body:
      {"Extra metadata for the post-processing of a command event.", "application/json",
       %Schema{
         deprecated: true,
         type: :object,
         properties: %{},
         required: []
       }},
    responses: %{
      no_content: "The command event artifact uploads were successfully finished",
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The command event doesn't exist", "application/json", Error}
    }
  )

  def complete_artifacts_uploads(%{path_params: %{"run_id" => run_id}} = conn, _params) do
    with {:ok, command_event} <- CommandEvents.get_command_event_by_id(run_id, preload: :project) do
      current_project = Authentication.current_project(conn)

      if FunWithFlags.enabled?(:flaky_test_detection, for: current_project) do
        # This is very slow. We should consider saving the necessary data in the db instead of fetching it on-demand from the S3 storage.
        test_summary =
          CommandEvents.get_test_summary(command_event)

        if not is_nil(test_summary) and not is_nil(current_project) do
          CommandEvents.create_test_cases(%{
            test_summary: test_summary,
            command_event: command_event
          })

          CommandEvents.create_test_case_runs(%{
            test_summary: test_summary,
            command_event: command_event
          })
        end
      end

      conn
      |> put_status(:no_content)
      |> json(%{})
    end
  end

  defp get_object_key(%{type: type, run_id: run_id, name: name}) do
    case CommandEvents.get_command_event_by_id(run_id) do
      {:ok, command_event} ->
        object_key =
          case type do
            "result_bundle" ->
              CommandEvents.get_result_bundle_key(command_event)

            "invocation_record" ->
              CommandEvents.get_result_bundle_invocation_record_key(command_event)

            "result_bundle_object" ->
              CommandEvents.get_result_bundle_object_key(command_event, name)
          end

        {:ok, object_key}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp bad_request_when_project_authenticated_from_non_ci_environment(%{body_params: body_params} = conn, _opts) do
    if is_nil(Authentication.current_project(conn)) or
         body_params.is_ci do
      conn
    else
      conn
      |> put_status(:bad_request)
      |> json(%{
        message:
          "Project authentication using a project-scoped token is not supported from non-CI environments. If you are running this from a CI environment, you can use the environment variable CI=1 to indicate so."
      })
      |> halt()
    end
  end
end
