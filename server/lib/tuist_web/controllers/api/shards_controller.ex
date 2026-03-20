defmodule TuistWeb.API.ShardsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Shards
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.Shards.Shard
  alias TuistWeb.API.Schemas.Shards.ShardPlan

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags(["Shards"])

  operation(:create,
    summary: "Create a shard plan.",
    description: "Creates a new test sharding session that distributes test targets across multiple CI runners.",
    operation_id: "createShardPlan",
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
      {"Shard plan params", "application/json",
       %Schema{
         title: "CreateShardPlanParams",
         type: :object,
         properties: %{
           reference: %Schema{
             type: :string,
             description: "A unique shard plan reference, typically derived from CI environment."
           },
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
         required: [:reference, :modules]
       }},
    responses: %{
      ok: {"The shard plan", "application/json", ShardPlan},
      unauthorized: {"You need to be authenticated", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized", "application/json", Error},
      not_found: {"The project doesn't exist", "application/json", Error},
      bad_request: {"Invalid parameters", "application/json", Error}
    }
  )

  def create(%{assigns: %{selected_project: selected_project}, body_params: body_params} = conn, _params) do
    params = %{
      reference: body_params.reference,
      modules: Map.get(body_params, :modules),
      test_suites: Map.get(body_params, :test_suites),
      shard_min: Map.get(body_params, :shard_min),
      shard_max: Map.get(body_params, :shard_max),
      shard_total: Map.get(body_params, :shard_total),
      shard_max_duration: Map.get(body_params, :shard_max_duration),
      granularity: Map.get(body_params, :granularity, "module")
    }

    result = Shards.create_shard_plan(selected_project, params)

    json(conn, %{
      id: result.plan.id,
      reference: result.plan.reference,
      shard_count: result.shard_count,
      shards: result.shard_assignments
    })
  end

  operation(:start_upload,
    summary: "Start a multipart upload for the test products bundle.",
    operation_id: "startShardUpload",
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
      {"Start upload params", "application/json",
       %Schema{
         title: "StartShardUploadParams",
         type: :object,
         properties: %{
           reference: %Schema{type: :string, description: "The shard plan reference."}
         },
         required: [:reference]
       }},
    responses: %{
      ok:
        {"The upload ID", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :object,
               properties: %{upload_id: %Schema{type: :string}}
             }
           }
         }},
      unauthorized: {"You need to be authenticated", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized", "application/json", Error}
    }
  )

  def start_upload(
        %{assigns: %{selected_project: selected_project}, body_params: %{reference: reference}} = conn,
        _params
      ) do
    {:ok, upload_id} =
      Shards.start_upload(
        selected_project,
        selected_project.account,
        reference
      )

    json(conn, %{data: %{upload_id: upload_id}})
  end

  operation(:show,
    summary: "Get a shard.",
    description: "Returns the test targets and download URLs for a specific shard.",
    operation_id: "getShard",
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
      reference: [
        in: :path,
        type: :string,
        required: true,
        description: "The shard plan reference."
      ],
      shard_index: [
        in: :path,
        type: :integer,
        required: true,
        description: "The zero-based shard index."
      ]
    ],
    responses: %{
      ok: {"The shard", "application/json", Shard},
      unauthorized: {"You need to be authenticated", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized", "application/json", Error},
      not_found: {"The session or shard was not found", "application/json", Error}
    }
  )

  def show(
        %{
          assigns: %{selected_project: selected_project},
          path_params: %{"reference" => reference, "shard_index" => shard_index}
        } = conn,
        _params
      ) do
    shard_index = if is_binary(shard_index), do: String.to_integer(shard_index), else: shard_index

    case Shards.get_shard(
           selected_project,
           selected_project.account,
           reference,
           shard_index
         ) do
      {:ok, result} ->
        json(conn, %{
          shard_plan_id: result.shard_plan_id,
          modules: result.modules,
          suites: result.suites,
          download_url: result.download_url
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The shard plan was not found."})

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
           reference: %Schema{type: :string, description: "The shard plan reference."},
           upload_id: %Schema{type: :string, description: "The multipart upload ID."},
           part_number: %Schema{type: :integer, description: "The part number."}
         },
         required: [:reference, :upload_id, :part_number]
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
      forbidden: {"The authenticated subject is not authorized", "application/json", Error}
    }
  )

  def generate_url(
        %{
          assigns: %{selected_project: selected_project},
          body_params: %{reference: reference, upload_id: upload_id, part_number: part_number}
        } = conn,
        _params
      ) do
    {:ok, url} =
      Shards.generate_upload_url(
        selected_project,
        selected_project.account,
        reference,
        upload_id,
        part_number
      )

    json(conn, %{data: %{url: url}})
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
           reference: %Schema{type: :string, description: "The shard plan reference."},
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
         required: [:reference, :upload_id, :parts]
       }},
    responses: %{
      ok:
        {"Upload completed", "application/json",
         %Schema{
           type: :object,
           properties: %{status: %Schema{type: :string}}
         }},
      unauthorized: {"You need to be authenticated", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized", "application/json", Error}
    }
  )

  def complete(
        %{
          assigns: %{selected_project: selected_project},
          body_params: %{reference: reference, upload_id: upload_id, parts: parts}
        } = conn,
        _params
      ) do
    parts_list =
      Enum.map(parts, fn part ->
        {part.part_number, part.etag}
      end)

    :ok =
      Shards.complete_upload(
        selected_project,
        selected_project.account,
        reference,
        upload_id,
        parts_list
      )

    json(conn, %{status: "success"})
  end
end
