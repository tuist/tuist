defmodule CacheWeb.KeyValueController do
  use CacheWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Cache.KeyValueStore
  alias CacheWeb.API.Schemas.Error
  alias CacheWeb.API.Schemas.KeyValueResponse
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true

  tags(["KeyValue"])

  operation(:get_value,
    summary: "Get a key-value entry",
    operation_id: "getKeyValue",
    parameters: [
      cas_id: [
        in: :path,
        type: :string,
        required: true,
        description: "The CAS ID"
      ],
      account_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the account"
      ],
      project_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project"
      ]
    ],
    responses: %{
      ok: {"Key-value entry", "application/json", KeyValueResponse},
      not_found: {"Entry not found", "application/json", Error},
      unauthorized: {"Unauthorized", "application/json", Error},
      bad_request: {"Bad request", "application/json", Error}
    }
  )

  def get_value(conn, %{cas_id: cas_id, account_handle: account_handle, project_handle: project_handle}) do
    :telemetry.execute([:cache, :kv, :get, :request], %{count: 1}, %{})

    case KeyValueStore.get_key_value(cas_id, account_handle, project_handle) do
      {:ok, payload} ->
        :telemetry.execute([:cache, :kv, :get, :hit], %{count: 1, bytes: byte_size(payload)}, %{})

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(:ok, payload)

      {:error, :not_found} ->
        :telemetry.execute([:cache, :kv, :get, :miss], %{count: 1}, %{})

        conn
        |> put_status(:not_found)
        |> json(%{message: "No entries found for CAS ID #{cas_id}."})
    end
  end

  operation(:put_value,
    summary: "Put a key-value entry",
    operation_id: "putKeyValue",
    parameters: [
      account_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the account"
      ],
      project_handle: [
        in: :query,
        type: :string,
        required: true,
        description: "The handle of the project"
      ]
    ],
    request_body:
      {"Key-value entry data", "application/json",
       %Schema{
         type: :object,
         properties: %{
           cas_id: %Schema{type: :string, description: "The CAS ID"},
           entries: %Schema{
             type: :array,
             items: %Schema{
               type: :object,
               properties: %{
                 value: %Schema{type: :string, description: "The value"}
               }
             }
           }
         },
         required: [:cas_id, :entries]
       }, required: true},
    responses: %{
      no_content: {"Success", nil, nil},
      unauthorized: {"Unauthorized", "application/json", Error},
      bad_request: {"Bad request", "application/json", Error}
    }
  )

  def put_value(conn, %{account_handle: account_handle, project_handle: project_handle}) do
    :telemetry.execute([:cache, :kv, :put, :request], %{count: 1}, %{})
    %{cas_id: cas_id, entries: entries} = conn.body_params
    values = Enum.map(entries, fn entry -> entry.value end)

    case KeyValueStore.put_key_value(cas_id, account_handle, project_handle, values) do
      :ok ->
        :telemetry.execute([:cache, :kv, :put, :success], %{entries_count: length(values)}, %{})

      {:error, reason} ->
        :telemetry.execute([:cache, :kv, :put, :error], %{count: 1}, %{reason: inspect(reason)})
    end

    send_resp(conn, :no_content, "")
  end
end
