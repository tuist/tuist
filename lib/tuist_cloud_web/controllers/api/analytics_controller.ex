defmodule TuistCloudWeb.API.AnalyticsController do
  use OpenApiSpex.ControllerSpecs
  use TuistCloudWeb, :controller
  alias TuistCloudWeb.API.Schemas.ArtifactMultipartUploadUrl
  alias TuistCloudWeb.API.Schemas.ArtifactMultipartUploadParts
  alias TuistCloudWeb.API.Schemas.ArtifactMultipartUploadPart
  alias TuistCloudWeb.API.Schemas.CommandEventArtifact
  alias TuistCloud.Storage
  alias TuistCloudWeb.API.Schemas.ArtifactUploadId
  alias TuistCloud.Repo
  alias TuistCloudWeb.API.EnsureProjectPresencePlug
  alias TuistCloud.CommandEvents
  alias TuistCloudWeb.Authentication
  alias OpenApiSpex.Schema
  alias TuistCloudWeb.API.Schemas.{Error, CommandEvent}

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistCloudWeb.RenderAPIErrorPlug
  )

  plug(TuistCloudWeb.API.EnsureProjectPresencePlug)
  plug(TuistCloudWeb.API.Authorization.AuthorizationPlug, :command_event)

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
        error_message: Map.get(body_params, :error_message)
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
          body_params: %{
            "type" => type
          }
        } = conn,
        _params
      ) do
    upload_id =
      Storage.multipart_start(object_key(%{type: type, run_id: run_id}))

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
            command_event_artifact: %{
              "type" => type
            },
            multipart_upload_part: %{
              "part_number" => part_number,
              "upload_id" => upload_id
            }
          }
        } = conn,
        _params
      ) do
    expires_in = 120

    url =
      Storage.multipart_generate_url(
        object_key(%{type: type, run_id: run_id}),
        upload_id,
        part_number,
        expires_in: expires_in
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
      forbidden:
        {"The authenticated subject is not authorized to perform this action", "application/json",
         Error},
      not_found: {"The project doesn't exist", "application/json", Error}
    }
  )

  def multipart_complete(
        %{
          path_params: %{
            "run_id" => run_id
          },
          body_params: %{
            command_event_artifact: %{
              "type" => type
            },
            multipart_upload_parts: %ArtifactMultipartUploadParts{
              parts: parts,
              upload_id: upload_id
            }
          }
        } = conn,
        _params
      ) do
    :ok =
      Storage.multipart_complete_upload(
        object_key(%{type: type, run_id: run_id}),
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

  defp object_key(%{type: type, run_id: run_id}) do
    command_event = CommandEvents.get_command_event_by_id(run_id)

    case type do
      "result_bundle" ->
        CommandEvents.get_result_bundle_object_key(command_event)
    end
  end
end
