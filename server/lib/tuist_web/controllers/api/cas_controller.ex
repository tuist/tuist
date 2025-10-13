defmodule TuistWeb.API.CASController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.CAS
  alias Tuist.Projects
  alias Tuist.Storage
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication

  plug(OpenApiSpex.Plug.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  tags ["CAS"]

  operation(:prefix,
    summary: "Get the S3 object key prefix for a project's CAS storage.",
    operation_id: "getCASPrefix",
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
    responses: %{
      ok:
        {"The CAS storage prefix", "application/json",
         %Schema{
           type: :object,
           properties: %{
             prefix: %Schema{
               type: :string,
               description: "The S3 object key prefix where CAS objects should be stored.",
               example: "account-123/project-456/xcode/cas/"
             }
           },
           required: [:prefix]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def prefix(conn, _params) do
    %{account_handle: account_handle, project_handle: project_handle} = conn.private.open_api_spex.params
    authenticated_subject = Authentication.authenticated_subject(conn)
    account = Accounts.get_account_by_handle(account_handle)

    project =
      if is_nil(account),
        do: nil,
        else: Projects.get_project_by_account_and_project_handles(account.name, project_handle, preload: [:account])

    cond do
      is_nil(account) ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "Account #{account_handle} not found."})

      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> json(%Error{message: "Project #{account_handle}/#{project_handle} not found."})

      Authorization.authorize(:cas_read, authenticated_subject, project) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%Error{
          message: "You don't have permission to access the #{project.name} project."
        })

      true ->
        prefix = "#{project.account.name}/#{project.name}/cas/"

        conn
        |> put_status(:ok)
        |> json(%{prefix: prefix})
    end
  end

  operation(:show,
    summary: "Download a CAS artifact.",
    operation_id: "getCASArtifact",
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
      ],
      id: [
        in: :path,
        type: :string,
        required: true,
        description: "The artifact identifier."
      ]
    ],
    responses: %{
      ok: {"Artifact content stream", "application/octet-stream", nil},
      not_found: {"Artifact does not exist", "application/json", nil},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error}
    }
  )

  def show(conn, _params) do
    %{id: id, account_handle: account_handle, project_handle: project_handle} = conn.private.open_api_spex.params
    authenticated_subject = Authentication.authenticated_subject(conn)
    account = Accounts.get_account_by_handle(account_handle)

    project =
      if is_nil(account),
        do: nil,
        else: Projects.get_project_by_account_and_project_handles(account.name, project_handle, preload: [:account])

    cond do
      is_nil(account) ->
        conn
        |> put_status(:not_found)
        |> send_resp(:not_found, "")

      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> send_resp(:not_found, "")

      Authorization.authorize(:cas_read, authenticated_subject, project) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%Error{
          message: "You don't have permission to access the #{project.name} project."
        })

      true ->
        prefix = "#{project.account.name}/#{project.name}/cas/"
        key = "#{prefix}#{get_s3_key(id)}"

        if Storage.object_exists?(key, authenticated_subject) do
          stream = Storage.stream_object(key, authenticated_subject)

          conn
          |> put_resp_content_type("application/octet-stream")
          |> send_chunked(200)
          |> stream_data(stream)
        else
          send_resp(conn, :not_found, "")
        end
    end
  end

  defp stream_data(conn, stream) do
    Enum.reduce_while(stream, conn, fn chunk, conn ->
      case chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, :closed} -> {:halt, conn}
      end
    end)
  end

  operation(:create,
    summary: "Upload a CAS artifact (or verify it already exists).",
    operation_id: "uploadCASArtifact",
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
      ],
      id: [
        in: :path,
        type: :string,
        required: true,
        description: "The artifact identifier."
      ]
    ],
    request_body: {"The CAS artifact data", "application/octet-stream", nil, required: true},
    responses: %{
      ok: {"Upload successful", "application/json", %Schema{type: :object,
      title: "CASArtifact",
      properties: %{id: %Schema{type: :string}}}},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error}
    }
  )

  def create(conn, _params) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, length: 100_000_000)
    %{id: id, account_handle: account_handle, project_handle: project_handle} = conn.private.open_api_spex.params
    authenticated_subject = Authentication.authenticated_subject(conn)
    account = Accounts.get_account_by_handle(account_handle)

    project =
      if is_nil(account),
        do: nil,
        else: Projects.get_project_by_account_and_project_handles(account.name, project_handle, preload: [:account])

    cond do
      is_nil(account) ->
        conn
        |> put_status(:not_found)
        |> send_resp(:not_found, "")

      is_nil(project) ->
        conn
        |> put_status(:not_found)
        |> send_resp(:not_found, "")

      Authorization.authorize(:cas_create, authenticated_subject, project) != :ok ->
        conn
        |> put_status(:forbidden)
        |> json(%Error{
          message: "You don't have permission to write to the #{project.name} project."
        })

      true ->
        prefix = "#{project.account.name}/#{project.name}/cas/"
        key = "#{prefix}#{get_s3_key(id)}"

        if Storage.object_exists?(key, authenticated_subject) do
          conn
          |> put_status(:ok)
          |> json(%{id: "key"})
        else
          # Stream the upload from the request body to S3
          Storage.put_object(key, body, authenticated_subject)
          conn
          |> put_status(:ok)
          |> json(%{id: key})
        end
    end
  end

  operation(:put_value,
    summary: "Store CAS key-value entries.",
    operation_id: "putCASValue",
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
            additionalProperties: %Schema{type: :string}
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

  def put_value(conn, _params) do
    dbg("Putting value...")
    %{account_handle: account_handle, project_handle: project_handle} =
      conn.private.open_api_spex.params

    %{"cas_id" => cas_id, "entries" => entries} = conn.private.open_api_spex.body
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
          Enum.map(entries, fn {key, value} ->
            entry_attrs = %{
              cas_id: cas_id,
              key: key,
              value: value,
              project_id: project.id,
              inserted_at: NaiveDateTime.utc_now()
            }

            {:ok, entry} = CAS.create_entry(entry_attrs)
            entry
          end)

        conn
        |> put_status(:ok)
        |> json(%{count: length(inserted_entries)})
    end
  end

  # Convert CAS ID to S3 key format by replacing ~ with /
  # Format: {version}~{hash} -> {version}/{hash}
  # Example: 0~YWoYNXX... -> 0/YWoYNXX...
  defp get_s3_key(cas_id) do
    String.replace(cas_id, "~", "/")
  end
end
