defmodule TuistWeb.API.Cache.KeyValueController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Cache
  alias TuistWeb.API.Cache.Plugs.LoaderQueryPlug
  alias TuistWeb.API.Schemas.Error

  plug(LoaderQueryPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :cache)

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  tags ["KeyValue"]

  operation(:get_value,
    summary: "Get cache value.",
    operation_id: "getCacheValue",
    parameters: [
      cas_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The CAS identifier."
      ],
      account_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project's account."
      ],
      project_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project."
      ]
    ],
    responses: %{
      ok: {
        "Cache value retrieved successfully",
        "application/json",
        %Schema{
          type: :object,
          properties: %{
            entries: %Schema{
              type: :array,
              items: %Schema{
                type: :object,
                properties: %{
                  value: %Schema{type: :string, description: "The value of the entry"}
                },
                required: [:value]
              }
            }
          },
          required: [:entries]
        }
      },
      unauthorized: {
        "You need to be authenticated to access this resource",
        "application/json",
        Error
      },
      forbidden: {
        "The authenticated subject is not authorized to perform this action",
        "application/json",
        Error
      },
      not_found: {"No entries found for the given CAS ID", "application/json", Error},
      bad_request: {"The request is invalid", "application/json", Error}
    }
  )

  def get_value(%{assigns: %{selected_project: project}} = conn, %{cas_id: cas_id} = _params) do
    values = Cache.get_key_value(cas_id, project.id)

    case values do
      [] ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "No entries found for CAS ID #{cas_id}."})

      _ ->
        conn
        |> put_status(:ok)
        |> json(%{"entries" => Enum.map(values, fn value -> %{"value" => value} end)})
    end
  end

  operation(:put_value,
    summary: "Store cache key value entries.",
    operation_id: "putCacheValue",
    parameters: [
      account_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project's account."
      ],
      project_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project."
      ]
    ],
    request_body: {
      "CAS entries with CAS ID",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          cas_id: %Schema{type: :string, description: "The CAS identifier"},
          entries: %Schema{
            description: "Map of entry keys to encoded values",
            type: :array,
            items: %Schema{
              type: :object,
              properties: %{
                value: %Schema{type: :string, description: "The value of the entry"}
              },
              required: [:value]
            }
          }
        },
        required: [:cas_id, :entries]
      },
      required: true
    },
    responses: %{
      no_content: {"Value stored successfully", nil, nil},
      unauthorized: {
        "You need to be authenticated to access this resource",
        "application/json",
        Error
      },
      forbidden: {
        "The authenticated subject is not authorized to perform this action",
        "application/json",
        Error
      },
      not_found: {"The project was not found", "application/json", Error},
      bad_request: {"The request is invalid", "application/json", Error}
    }
  )

  def put_value(
        %{assigns: %{selected_project: project}, body_params: %{entries: entries, cas_id: cas_id}} = conn,
        _params
      ) do
    values = Enum.map(entries, fn entry -> entry.value end)
    :ok = Cache.put_key_value(cas_id, project.id, values)

    send_resp(conn, :no_content, "")
  end
end
