defmodule TuistWeb.API.AnalyticsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller
  alias Tuist.VCS
  alias TuistWeb.API.Schemas.Module
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadUrl
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadParts
  alias TuistWeb.API.Schemas.ArtifactMultipartUploadPart
  alias TuistWeb.API.Schemas.CommandEventArtifact
  alias Tuist.Storage
  alias TuistWeb.API.Schemas.ArtifactUploadId
  alias Tuist.Repo
  alias TuistWeb.API.EnsureProjectPresencePlug
  alias Tuist.CommandEvents
  alias TuistWeb.Authentication
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.{Error, CommandEvent}

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.API.EnsureProjectPresencePlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :command_event)

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
             type: :number,
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
           params: %Schema{
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
           preview_id: %Schema{
             type: :string,
             description: "The preview identifier."
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
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden:
        {"You don't have permission to create command events for the project.",
         "application/json", Error}
    }
  )

  def create(
        %{
          body_params: body_params
        } = conn,
        _params
      ) do
    current_user = Authentication.current_user(conn)

    user_id =
      if is_nil(current_user) do
        nil
      else
        current_user.id
      end

    project =
      EnsureProjectPresencePlug.get_project(conn)
      |> Repo.preload(:account)

    git_commit_sha = Map.get(body_params, :git_commit_sha)
    git_ref = Map.get(body_params, :git_ref)
    git_remote_url_origin = Map.get(body_params, :git_remote_url_origin)
    preview_id = Map.get(body_params, :preview_id)

    command_event =
      CommandEvents.create_command_event(%{
        name: body_params.name,
        subcommand: Map.get(body_params, :subcommand, nil),
        command_arguments: body_params.command_arguments,
        duration: body_params.duration,
        tuist_version: body_params.tuist_version,
        swift_version: body_params.swift_version,
        macos_version: body_params.macos_version,
        cacheable_targets: Map.get(body_params.params, :cacheable_targets, []),
        local_cache_target_hits: Map.get(body_params.params, :local_cache_target_hits, []),
        remote_cache_target_hits: Map.get(body_params.params, :remote_cache_target_hits, []),
        test_targets: Map.get(body_params.params, :test_targets, []),
        local_test_target_hits: Map.get(body_params.params, :local_test_target_hits, []),
        remote_test_target_hits: Map.get(body_params.params, :remote_test_target_hits, []),
        is_ci: body_params.is_ci,
        user_id: user_id,
        client_id: body_params.client_id,
        project_id: project.id,
        status: Map.get(body_params, :status),
        error_message: Map.get(body_params, :error_message),
        preview_id: preview_id,
        git_commit_sha: git_commit_sha,
        git_ref: git_ref,
        git_remote_url_origin: git_remote_url_origin
      })

    VCS.post_vcs_pull_request_comment(%{
      command_name: body_params.name,
      git_commit_sha: git_commit_sha,
      git_ref: git_ref,
      git_remote_url_origin: git_remote_url_origin,
      project: project,
      preview_url:
        &url(~p"/#{&1.project.account.name}/#{&1.project.name}/previews/#{&1.preview.id}"),
      preview_qr_code_url:
        &url(
          ~p"/#{&1.project.account.name}/#{&1.project.name}/previews/#{&1.preview.id}/qr-code.svg"
        ),
      command_run_url:
        &url(~p"/#{&1.project.account.name}/#{&1.project.name}/runs/#{&1.command_event.id}")
    })

    conn
    |> put_status(:ok)
    |> json(%{
      id: command_event.id,
      project_id: command_event.project_id,
      name: command_event.name,
      url: url(~p"/#{project.account.name}/#{project.name}/runs/#{command_event.id}")
    })
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
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The command event doesn't exist", "application/json", Error}
    }
  )

  def multipart_start(
        %{
          path_params: %{
            "run_id" => run_id
          },
          body_params:
            %{
              "type" => type
            } = command_event_artifact
        } = conn,
        _params
      ) do
    upload_id =
      Storage.multipart_start(
        get_object_key(%{type: type, run_id: run_id, name: command_event_artifact["name"]})
      )

    conn |> json(%{status: "success", data: %{upload_id: upload_id}})
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
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project doesn't exist", "application/json", Error}
    }
  )

  def multipart_generate_url(
        %{
          path_params: %{
            "run_id" => run_id
          },
          body_params: %{
            command_event_artifact:
              %{
                "type" => type
              } = command_event_artifact,
            multipart_upload_part:
              %{
                "part_number" => part_number,
                "upload_id" => upload_id
              } = multipart_upload_part
          }
        } = conn,
        _params
      ) do
    expires_in = 120
    content_length = Map.get(multipart_upload_part, "content_length")

    url =
      Storage.multipart_generate_url(
        get_object_key(%{type: type, run_id: run_id, name: command_event_artifact["name"]}),
        upload_id,
        part_number,
        expires_in: expires_in,
        content_length: content_length
      )

    conn |> json(%{status: "success", data: %{url: url}})
  end

  operation(:multipart_complete,
    summary: "It completes a multi-part upload.",
    description:
      "Given the upload ID and all the parts with their ETags, this endpoint completes the multipart upload.",
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
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      internal_server_error: {"An internal server error occurred", "application/json", Error}
    }
  )

  def multipart_complete(
        %{
          path_params: %{
            "run_id" => run_id
          },
          body_params: %{
            command_event_artifact:
              %{
                "type" => type
              } = command_event_artifact,
            multipart_upload_parts: %ArtifactMultipartUploadParts{
              parts: parts,
              upload_id: upload_id
            }
          }
        } = conn,
        _params
      ) do
    object_key =
      get_object_key(%{type: type, run_id: run_id, name: command_event_artifact["name"]})

    :ok =
      Storage.multipart_complete_upload(
        object_key,
        upload_id,
        parts
        |> Enum.map(fn %{part_number: part_number, etag: etag} ->
          {part_number, etag}
        end)
      )

    conn
    |> put_status(:no_content)
    |> json(%{})
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
         type: :object,
         properties: %{
           modules: %Schema{
             type: :array,
             description: "A list of modules with their metadata.",
             items: Module
           }
         },
         required: [:modules]
       }},
    responses: %{
      no_content: "The command event artifact uploads were successfully finished",
      unauthorized:
        {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The command event doesn't exist", "application/json", Error}
    }
  )

  def complete_artifacts_uploads(
        %{
          path_params: %{
            "run_id" => run_id
          },
          body_params: %{
            modules: modules
          }
        } = conn,
        _params
      ) do
    modules =
      modules
      |> Enum.reduce(%{}, fn module, acc ->
        Map.update(
          acc,
          module.project_identifier,
          %{
            module.name => module.hash
          },
          fn project_map ->
            Map.put(project_map, module.name, module.hash)
          end
        )
      end)

    command_event =
      CommandEvents.get_command_event_by_id(run_id, preloads: :project)

    test_summary =
      CommandEvents.get_test_summary(command_event)

    if not is_nil(test_summary) do
      CommandEvents.create_test_cases(%{
        test_summary: test_summary,
        command_event: command_event
      })

      CommandEvents.create_test_case_runs(%{
        test_summary: test_summary,
        modules: modules,
        command_event: command_event
      })
    end

    conn
    |> put_status(:no_content)
    |> json(%{})
  end

  defp get_object_key(%{type: type, run_id: run_id, name: name}) do
    command_event = CommandEvents.get_command_event_by_id(run_id)

    case type do
      "result_bundle" ->
        CommandEvents.get_result_bundle_key(command_event)

      "invocation_record" ->
        CommandEvents.get_result_bundle_invocation_record_key(command_event)

      "result_bundle_object" ->
        CommandEvents.get_result_bundle_object_key(command_event, name)
    end
  end
end
