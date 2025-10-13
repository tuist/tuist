defmodule TuistWeb.API.Cache.KeyValueController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.CAS
  alias Tuist.Projects
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  tags ["KeyValue"]

  operation(:get_value,
    summary: "Get cache key value entries.",
    operation_id: "getKeyValue",
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
      ],
    ],
    responses: %{
      ok: {
        "Entries retrieved successfully",
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
      not_found: {"No entries found for the given CAS ID", "application/json", Error}
    }
  )

  def get_value(conn, %{cas_id: cas_id} = _params) do
    entries = CAS.get_entries_by_cas_id(cas_id)

    case entries do
      [] ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "No entries found for CAS ID #{cas_id}."})

      _ ->
        formatted_entries = Enum.map(entries, fn entry -> %{"value" => entry.value} end)

        conn
        |> put_status(:ok)
        |> json(%{"entries" => formatted_entries})
    end
  end

  operation(:put_value,
    summary: "Store cache key value entries.",
    operation_id: "putKeyValue",
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
      "CAS key-value data",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          cas_id: %Schema{type: :string, description: "The CAS identifier"},
          entries: %Schema{
            type: :object,
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
      ok: {
        "Entries stored successfully",
        "application/json",
        %Schema{type: :object, properties: %{count: %Schema{type: :integer}}}
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
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def put_value(
        %{
          body_params: %{
            entries: entries,
            cas_id: cas_id
          }
        } = conn,
        %{account_handle: account_handle, project_handle: project_handle} = _params
      ) do
    authenticated_subject = Authentication.authenticated_subject(conn)
    account = Accounts.get_account_by_handle(account_handle)

    project =
      if is_nil(account),
        do: nil,
        else:
          Projects.get_project_by_account_and_project_handles(account.name, project_handle,
            preload: [:account]
          )

    cond do
      is_nil(account) ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "Account #{account_handle} not found."})

      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "Project #{account_handle}/#{project_handle} not found."})

      Authorization.authorize(:cas_create, authenticated_subject, project) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%Error{
          message: "You don't have permission to write to the #{project.name} project."
        })

      true ->
        # Store each entry in ClickHouse
        inserted_entries =
          entries
          |> Enum.map(fn entry ->
            entry_attrs = %{
              cas_id: cas_id,
              value: entry.value,
              project_id: project.id,
              inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
            }

            {:ok, entry} = CAS.create_entry(entry_attrs)
            entry
          end)

        conn
        |> put_status(:ok)
        |> json(%{count: length(inserted_entries)})
    end
  end
end
