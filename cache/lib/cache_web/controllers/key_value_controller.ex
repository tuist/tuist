defmodule CacheWeb.KeyValueController do
  use CacheWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Cache.Authentication
  alias Cache.KeyValueStore
  alias CacheWeb.Schemas.Error

  plug OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true

  tags(["KeyValue"])

  operation(:get_value,
    summary: "Get cache key-value entries",
    operation_id: "getCacheKeyValue",
    parameters: [
      account_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project's account"
      ],
      project_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project"
      ],
      cas_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The CAS identifier"
      ]
    ],
    responses: %{
      200 =>
        {"Cache values retrieved successfully", "application/json",
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
         }},
      404 => {"No entries found for the given CAS ID", "application/json", Error}
    }
  )

  def get_value(conn, _params) do
    %{
      account_handle: account_handle,
      project_handle: project_handle,
      cas_id: cas_id
    } = conn.params

    case Authentication.ensure_project_accessible(conn, account_handle, project_handle) do
      {:ok, _auth_header} ->
        values = KeyValueStore.get_key_value(cas_id, account_handle, project_handle)

        case values do
          [] ->
            conn
            |> put_status(:not_found)
            |> json(%{message: "No entries found for CAS ID #{cas_id}."})

          _ ->
            conn
            |> put_status(:ok)
            |> json(%{entries: Enum.map(values, fn value -> %{value: value} end)})
        end

      {:error, status, message} ->
        conn
        |> put_status(status)
        |> json(%{message: message})
    end
  end

  operation(:put_value,
    summary: "Store cache key-value entries",
    operation_id: "putCacheKeyValue",
    parameters: [
      account_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project's account"
      ],
      project_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project"
      ]
    ],
    request_body: {
      "Key-value entries",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          cas_id: %Schema{type: :string, description: "The CAS identifier"},
          entries: %Schema{
            type: :array,
            items: %Schema{
              type: :object,
              properties: %{
                value: %Schema{type: :string, description: "The value of the entry"}
              },
              required: [:value]
            },
            description: "Array of entries to store",
            minItems: 1
          }
        },
        required: [:cas_id, :entries]
      },
      required: true
    },
    responses: %{
      204 => "Values stored successfully",
      400 => {"Invalid request", "application/json", Error}
    }
  )

  def put_value(conn, _params) do
    %{
      account_handle: account_handle,
      project_handle: project_handle
    } = conn.params

    %{cas_id: cas_id, entries: entries} = conn.body_params

    case Authentication.ensure_project_accessible(conn, account_handle, project_handle) do
      {:ok, _auth_header} ->
        # Extract just the values from the entries
        values = Enum.map(entries, fn entry -> entry.value end)

        :ok = KeyValueStore.put_key_value(cas_id, account_handle, project_handle, values)

        send_resp(conn, :no_content, "")

      {:error, status, message} ->
        conn
        |> put_status(status)
        |> json(%{message: message})
    end
  end
end
