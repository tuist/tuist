defmodule TuistCloudWeb.API.AnalyticsController do
  use OpenApiSpex.ControllerSpecs
  use TuistCloudWeb, :controller
  alias TuistCloudWeb.API.EnsureProjectPresencePlug
  alias TuistCloud.CommandEvents
  alias TuistCloudWeb.Authentication
  alias OpenApiSpex.Schema
  alias TuistCloudWeb.API.Schemas.{Error, CommandEvent}
  alias TuistCloud.Authorization

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistCloudWeb.RenderAPIErrorPlug
  )

  plug(TuistCloudWeb.API.EnsureProjectPresencePlug)

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
          query_params: %{
            "project_id" => project_id
          },
          body_params: body_params
        } = conn,
        _params
      ) do
    subject = Authentication.authenticated_subject(conn)
    current_user = Authentication.current_user(conn)

    user_id =
      if is_nil(current_user) do
        nil
      else
        Authentication.current_user(conn).id
      end

    project = EnsureProjectPresencePlug.get_project(conn)
    project_id = project_id

    if Authorization.can(subject, :create, project, :command_event) do
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
        name: command_event.name
      })
    else
      conn
      |> put_status(:forbidden)
      |> json(%Error{
        message: "You don't have permission to create command events for #{project_id}."
      })
    end
  end
end
