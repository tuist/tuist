defmodule Tuist.MCP.Components.Tools.StartProjectLogoUpload do
  @moduledoc """
  Start a project-logo upload. Returns a short-lived presigned URL the client
  PUTs the image bytes to, and a signed token that the caller must send back
  to `complete_project_logo_upload` to commit the new logo on the project.
  """

  use Tuist.MCP.Tool,
    name: "start_project_logo_upload",
    title: "Start Project Logo Upload",
    read_only_hint: false,
    destructive_hint: false,
    authorize: [action: :update, category: :project],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account or organization handle that owns the project."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The project handle."
        },
        "content_type" => %{
          "type" => "string",
          "enum" => ["image/png", "image/jpeg", "image/webp"],
          "description" => "MIME type of the logo the caller is about to upload."
        }
      },
      "required" => ["account_handle", "project_handle", "content_type"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "upload_url" => %{"type" => "string"},
        "method" => %{"type" => "string", "enum" => ["PUT"]},
        "content_type" => %{"type" => "string"},
        "upload_token" => %{"type" => "string"},
        "expires_at" => %{"type" => "string"},
        "expires_in_seconds" => %{"type" => "integer"},
        "storage_key" => %{"type" => "string"}
      },
      "required" => [
        "upload_url",
        "method",
        "content_type",
        "upload_token",
        "expires_at",
        "expires_in_seconds",
        "storage_key"
      ],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Formatter
  alias Tuist.Projects

  @impl EMCP.Tool
  def description,
    do:
      "Start a project-logo upload. Returns a presigned URL the client PUTs the image bytes to " <>
        "(within one hour), the request method and Content-Type header to use, and an upload_token. " <>
        "After PUT completes, call `complete_project_logo_upload` with the same account/project handles " <>
        "and the upload_token to commit the new logo. Accepted MIME types: image/png, image/jpeg, image/webp; " <>
        "files must be 2 MB or smaller."

  def execute(_conn, %{"content_type" => content_type}, project) do
    case Projects.prepare_project_logo_upload(project, content_type) do
      {:ok, prepared} ->
        {:ok,
         %{
           upload_url: prepared.upload_url,
           method: prepared.method,
           content_type: prepared.content_type,
           upload_token: prepared.upload_token,
           expires_at: Formatter.iso8601(prepared.expires_at),
           expires_in_seconds: prepared.expires_in_seconds,
           storage_key: prepared.storage_key
         }}

      {:error, :unsupported_logo_content_type} ->
        {:error, "Unsupported content_type. Use image/png, image/jpeg, or image/webp."}
    end
  end
end

defmodule Tuist.MCP.Components.Tools.CompleteProjectLogoUpload do
  @moduledoc """
  Commit a project logo whose bytes were PUT to the URL returned by
  `start_project_logo_upload`. Verifies the upload_token, confirms the object
  reached storage, and points the project at the new logo.
  """

  use Tuist.MCP.Tool,
    name: "complete_project_logo_upload",
    title: "Complete Project Logo Upload",
    read_only_hint: false,
    destructive_hint: true,
    authorize: [action: :update, category: :project],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account or organization handle that owns the project."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The project handle."
        },
        "upload_token" => %{
          "type" => "string",
          "description" => "The upload_token returned by start_project_logo_upload."
        }
      },
      "required" => ["account_handle", "project_handle", "upload_token"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "logo_url" => %{"type" => "string"},
        "storage_key" => %{"type" => "string"}
      },
      "required" => ["logo_url", "storage_key"],
      "additionalProperties" => false
    }

  alias Tuist.Environment
  alias Tuist.Projects

  @impl EMCP.Tool
  def description,
    do:
      "Commit a project logo previously uploaded via `start_project_logo_upload`. Verifies the " <>
        "upload_token, confirms the object exists in storage, and points the project at the new logo " <>
        "(replacing any previous one). Returns the public URL the logo is now served from."

  def execute(_conn, %{"upload_token" => upload_token}, project) do
    case Projects.finalize_project_logo_upload(project, upload_token) do
      {:ok, updated} ->
        {:ok,
         %{
           logo_url: logo_url(updated),
           storage_key: updated.logo_storage_key
         }}

      {:error, :logo_object_not_found} ->
        {:error,
         "No object at the storage key encoded in the upload_token. Ensure the PUT to upload_url succeeded, then retry."}

      {:error, :invalid_logo_upload_token} ->
        {:error, "The upload_token is invalid or has expired. Start a new upload with `start_project_logo_upload`."}

      {:error, :logo_upload_token_project_mismatch} ->
        {:error, "The upload_token was issued for a different project."}

      {:error, reason} ->
        {:error, "Could not finalize the logo upload: #{inspect(reason)}"}
    end
  end

  defp logo_url(project) do
    Environment.app_url(path: "/#{project.account.name}/#{project.name}/logo")
  end
end
