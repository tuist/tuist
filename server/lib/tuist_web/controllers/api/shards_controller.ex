defmodule TuistWeb.API.ShardsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Shards
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.Shards.ShardAssignment
  alias TuistWeb.API.Schemas.Shards.ShardSession

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags(["Shards"])

  operation(:create,
    summary: "Create a shard session.",
    description: "Creates a new test sharding session that distributes test targets across multiple CI runners.",
    operation_id: "createShardSession",
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
        description: "The handle of the project."
      ]
    ],
    request_body:
      {"Shard session params", "application/json",
       %Schema{
         title: "CreateShardSessionParams",
         type: :object,
         properties: %{
           session_id: %Schema{type: :string, description: "A unique session identifier."},
           modules: %Schema{
             type: :array,
             items: %Schema{type: :string},
             description: "Test module names (for module-level granularity)."
           },
           test_suites: %Schema{
             type: :array,
             items: %Schema{type: :string},
             description: "Test suite names (for suite-level granularity)."
           },
           shard_min: %Schema{type: :integer, description: "Minimum number of shards."},
           shard_max: %Schema{type: :integer, description: "Maximum number of shards."},
           shard_total: %Schema{type: :integer, description: "Exact number of shards."},
           shard_max_duration: %Schema{
             type: :integer,
             description: "Target maximum duration per shard in milliseconds."
           },
           granularity: %Schema{
             type: :string,
             enum: ["module", "suite"],
             description: "Sharding granularity level."
           }
         },
         required: [:session_id]
       }},
    responses: %{
      ok: {"The shard session", "application/json", ShardSession},
      unauthorized: {"You need to be authenticated", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      bad_request: {"Invalid parameters", "application/json", Error}
    }
  )

  def create(%{assigns: %{selected_project: selected_project}, body_params: body_params} = conn, _params) do
    params = %{
      session_id: body_params.session_id,
      modules: Map.get(body_params, :modules),
      test_suites: Map.get(body_params, :test_suites),
      shard_min: Map.get(body_params, :shard_min),
      shard_max: Map.get(body_params, :shard_max),
      shard_total: Map.get(body_params, :shard_total),
      shard_max_duration: Map.get(body_params, :shard_max_duration),
      granularity: Map.get(body_params, :granularity, "module")
    }

    case Shards.create_shard_session(selected_project, selected_project.account, params) do
      {:ok, result} ->
        json(conn, %{
          session_id: result.session.session_id,
          shard_count: result.shard_count,
          shards: result.shard_assignments,
          upload_id: result.upload_id
        })

      {:error, _changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "Invalid parameters."})
    end
  end

  operation(:show,
    summary: "Get a shard assignment.",
    description: "Returns the test targets and download URLs for a specific shard.",
    operation_id: "getShardAssignment",
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
        description: "The handle of the project."
      ],
      session_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The shard session identifier."
      ],
      shard_index: [
        in: :path,
        type: :integer,
        required: true,
        description: "The zero-based shard index."
      ]
    ],
    responses: %{
      ok: {"The shard assignment", "application/json", ShardAssignment},
      unauthorized: {"You need to be authenticated", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized", "application/json", Error},
      not_found: {"The session or shard was not found", "application/json", Error}
    }
  )

  def show(
        %{
          assigns: %{selected_project: selected_project},
          path_params: %{"session_id" => session_id, "shard_index" => shard_index}
        } = conn,
        _params
      ) do
    shard_index = if is_binary(shard_index), do: String.to_integer(shard_index), else: shard_index

    case Shards.get_shard_assignment(
           selected_project,
           selected_project.account,
           session_id,
           shard_index
         ) do
      {:ok, result} ->
        json(conn, %{
          test_targets: result.test_targets,
          xctestrun_download_url: result.xctestrun_download_url,
          bundle_download_url: result.bundle_download_url
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The shard session was not found."})

      {:error, :invalid_shard_index} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The shard index is out of range."})
    end
  end

  operation(:generate_url,
    summary: "Generate a signed URL for uploading a part of the test bundle.",
    operation_id: "generateShardUploadURL",
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
        description: "The handle of the project."
      ]
    ],
    request_body:
      {"Upload URL params", "application/json",
       %Schema{
         title: "GenerateShardUploadURLParams",
         type: :object,
         properties: %{
           session_id: %Schema{type: :string, description: "The shard session identifier."},
           upload_id: %Schema{type: :string, description: "The multipart upload ID."},
           part_number: %Schema{type: :integer, description: "The part number."}
         },
         required: [:session_id, :upload_id, :part_number]
       }},
    responses: %{
      ok:
        {"The signed URL", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :object,
               properties: %{url: %Schema{type: :string}}
             }
           }
         }},
      unauthorized: {"You need to be authenticated", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized", "application/json", Error},
      not_found: {"The session was not found", "application/json", Error}
    }
  )

  def generate_url(
        %{
          assigns: %{selected_project: selected_project},
          body_params: %{session_id: session_id, upload_id: upload_id, part_number: part_number}
        } = conn,
        _params
      ) do
    case Shards.generate_upload_url(
           selected_project,
           selected_project.account,
           session_id,
           upload_id,
           part_number
         ) do
      {:ok, url} ->
        json(conn, %{data: %{url: url}})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The shard session was not found."})
    end
  end

  operation(:generate_xctestrun_url,
    summary: "Generate a signed URL for uploading the .xctestrun file.",
    operation_id: "generateShardXctestrunUploadURL",
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
        description: "The handle of the project."
      ]
    ],
    request_body:
      {"Upload URL params", "application/json",
       %Schema{
         title: "GenerateShardXctestrunUploadURLParams",
         type: :object,
         properties: %{
           session_id: %Schema{type: :string, description: "The shard session identifier."}
         },
         required: [:session_id]
       }},
    responses: %{
      ok:
        {"The signed URL", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :object,
               properties: %{url: %Schema{type: :string}}
             }
           }
         }},
      unauthorized: {"You need to be authenticated", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized", "application/json", Error},
      not_found: {"The session was not found", "application/json", Error}
    }
  )

  def generate_xctestrun_url(
        %{assigns: %{selected_project: selected_project}, body_params: %{session_id: session_id}} = conn,
        _params
      ) do
    case Shards.generate_xctestrun_upload_url(
           selected_project,
           selected_project.account,
           session_id
         ) do
      {:ok, url} ->
        json(conn, %{data: %{url: url}})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The shard session was not found."})
    end
  end

  operation(:complete,
    summary: "Complete the multipart upload and trigger per-shard xctestrun creation.",
    operation_id: "completeShardUpload",
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
        description: "The handle of the project."
      ]
    ],
    request_body:
      {"Complete upload params", "application/json",
       %Schema{
         title: "CompleteShardUploadParams",
         type: :object,
         properties: %{
           session_id: %Schema{type: :string, description: "The shard session identifier."},
           upload_id: %Schema{type: :string, description: "The multipart upload ID."},
           parts: %Schema{
             type: :array,
             description: "The uploaded parts with their ETags.",
             items: %Schema{
               type: :object,
               properties: %{
                 part_number: %Schema{type: :integer},
                 etag: %Schema{type: :string}
               },
               required: [:part_number, :etag]
             }
           }
         },
         required: [:session_id, :upload_id, :parts]
       }},
    responses: %{
      ok:
        {"Upload completed", "application/json",
         %Schema{
           type: :object,
           properties: %{status: %Schema{type: :string}}
         }},
      unauthorized: {"You need to be authenticated", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized", "application/json", Error},
      not_found: {"The session was not found", "application/json", Error}
    }
  )

  def complete(
        %{
          assigns: %{selected_project: selected_project},
          body_params: %{session_id: session_id, upload_id: upload_id, parts: parts}
        } = conn,
        _params
      ) do
    parts_list =
      Enum.map(parts, fn part ->
        {part.part_number, part.etag}
      end)

    case Shards.complete_upload(
           selected_project,
           selected_project.account,
           session_id,
           upload_id,
           parts_list
         ) do
      {:ok, _session} ->
        json(conn, %{status: "success"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The shard session was not found."})
    end
  end
end
