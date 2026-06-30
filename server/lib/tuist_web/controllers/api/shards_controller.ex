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
           },
           build_run_id: %Schema{
             type: :string,
             format: :uuid,
             description: "The UUID of the associated Xcode build run."
           },
           gradle_build_id: %Schema{
             type: :string,
             format: :uuid,
             description: "The UUID of the associated Gradle build."
           }
         },
         required: [:reference]
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
      granularity: Map.get(body_params, :granularity, "module"),
      build_run_id: Map.get(body_params, :build_run_id),
      gradle_build_id: Map.get(body_params, :gradle_build_id)
    }

    result = Shards.create_shard_plan(selected_project, params)

    response = %{
      id: result.plan.id,
      reference: result.plan.reference,
      shard_count: result.shard_count,
      upload_url:
        url(~p"/api/projects/#{selected_project.account.name}/#{selected_project.name}/tests/shards/upload/start"),
      shards: result.shard_assignments
    }

    json(conn, response)
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
           shard_plan_id: %Schema{
             type: :string,
             format: :uuid,
             description: "The shard plan id returned by createShardPlan."
           },
           reference: %Schema{type: :string, description: "The shard plan reference."}
         }
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
      forbidden: {"The authenticated subject is not authorized", "application/json", Error},
      not_found: {"The shard plan was not found", "application/json", Error},
      bad_request: {"Invalid parameters", "application/json", Error}
    }
  )

  def start_upload(%{assigns: %{selected_project: selected_project}, body_params: body_params} = conn, _params) do
    result =
      case upload_identifier(body_params) do
        {:plan_id, plan_id} ->
          Shards.start_upload_for_plan_id(selected_project, selected_project.account, plan_id)

        {:reference, reference} ->
          Shards.start_upload(selected_project, selected_project.account, reference)

        {:error, :missing_shard_plan_identifier} ->
          {:error, :missing_shard_plan_identifier}
      end

    case result do
      {:ok, upload_id} ->
        json(conn, %{data: %{upload_id: upload_id}})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The shard plan was not found."})

      {:error, :missing_shard_plan_identifier} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "Either shard_plan_id or reference is required."})
    end
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
          skip: result.skip,
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
           shard_plan_id: %Schema{
             type: :string,
             format: :uuid,
             description: "The shard plan id returned by createShardPlan."
           },
           reference: %Schema{type: :string, description: "The shard plan reference."},
           upload_id: %Schema{type: :string, description: "The multipart upload ID."},
           part_number: %Schema{type: :integer, description: "The part number."}
         },
         required: [:upload_id, :part_number]
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
      bad_request: {"Invalid parameters", "application/json", Error}
    }
  )

  def generate_url(
        %{
          assigns: %{selected_project: selected_project},
          body_params: %{upload_id: upload_id, part_number: part_number} = body_params
        } = conn,
        _params
      ) do
    result =
      case upload_identifier(body_params) do
        {:plan_id, plan_id} ->
          Shards.generate_upload_url_for_plan(
            selected_project,
            selected_project.account,
            plan_id,
            upload_id,
            part_number
          )

        {:reference, reference} ->
          Shards.generate_upload_url(
            selected_project,
            selected_project.account,
            reference,
            upload_id,
            part_number
          )

        {:error, :missing_shard_plan_identifier} ->
          {:error, :missing_shard_plan_identifier}
      end

    case result do
      {:ok, url} ->
        json(conn, %{data: %{url: url}})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The shard plan was not found."})

      {:error, :missing_shard_plan_identifier} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "Either shard_plan_id or reference is required."})
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
           shard_plan_id: %Schema{
             type: :string,
             format: :uuid,
             description: "The shard plan id returned by createShardPlan."
           },
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
         required: [:upload_id, :parts]
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
      bad_request: {"Invalid parameters", "application/json", Error}
    }
  )

  def complete(
        %{
          assigns: %{selected_project: selected_project},
          body_params: %{upload_id: upload_id, parts: parts} = body_params
        } = conn,
        _params
      ) do
    parts_list =
      Enum.map(parts, fn part ->
        {part.part_number, part.etag}
      end)

    result =
      case upload_identifier(body_params) do
        {:plan_id, plan_id} ->
          Shards.complete_upload_for_plan(
            selected_project,
            selected_project.account,
            plan_id,
            upload_id,
            parts_list
          )

        {:reference, reference} ->
          Shards.complete_upload(
            selected_project,
            selected_project.account,
            reference,
            upload_id,
            parts_list
          )

        {:error, :missing_shard_plan_identifier} ->
          {:error, :missing_shard_plan_identifier}
      end

    case result do
      :ok ->
        json(conn, %{status: "success"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The shard plan was not found."})

      {:error, :missing_shard_plan_identifier} ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "Either shard_plan_id or reference is required."})
    end
  end

  defp upload_identifier(body_params) do
    shard_plan_id = Map.get(body_params, :shard_plan_id)
    reference = Map.get(body_params, :reference)

    cond do
      is_binary(shard_plan_id) and shard_plan_id != "" -> {:plan_id, shard_plan_id}
      is_binary(reference) and reference != "" -> {:reference, reference}
      true -> {:error, :missing_shard_plan_identifier}
    end
  end
end
