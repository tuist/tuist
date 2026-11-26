defmodule Atlas.MCP.Serializers.SocialPublishing do
  @moduledoc false

  alias Atlas.GTM.SocialAccounts
  alias Atlas.GTM.SocialPublication
  alias Atlas.GTM.SocialPublishing
  alias Atlas.MCP.Tool

  def publication_schema do
    %{
      "type" => "object",
      "required" => ["id", "account", "status", "revision", "scheduled_at", "items"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "account" => %{"type" => ["string", "null"]},
        "status" => %{"type" => "string", "enum" => SocialPublication.statuses()},
        "revision" => %{"type" => "integer"},
        "scheduled_at" => %{"type" => "string"},
        "items" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "text" => %{"type" => "string"},
              "media_ids" => %{"type" => "array", "items" => %{"type" => "string"}}
            }
          }
        },
        "approved_by" => %{"type" => ["string", "null"]},
        "approved_at" => %{"type" => ["string", "null"]},
        "url" => %{"type" => ["string", "null"]},
        "published_at" => %{"type" => ["string", "null"]},
        "error" => %{"type" => ["string", "null"]},
        "dashboard_url" => %{"type" => "string"}
      }
    }
  end

  def publication(%SocialPublication{} = publication) do
    %{
      id: publication.id,
      account: publication.social_account && publication.social_account.handle,
      status: publication.status,
      revision: publication.revision,
      scheduled_at: Tool.iso8601(publication.scheduled_at),
      items: publication.items,
      approved_by: publication.approved_by && (publication.approved_by.name || publication.approved_by.email),
      approved_at: Tool.iso8601(publication.approved_at),
      url: SocialPublication.url(publication),
      published_at: Tool.iso8601(publication.published_at),
      error: publication.last_error,
      dashboard_url: AtlasWeb.Endpoint.url() <> SocialPublishing.dashboard_path() <> "/" <> publication.id
    }
  end

  @doc "The connected X account with this handle, such as @tuistdev."
  def account_id(nil), do: {:ok, nil}

  def account_id(handle) do
    handle = "@" <> String.trim_leading(handle, "@")

    case Enum.find(SocialAccounts.list(), &(&1.platform == "x" and &1.handle == handle)) do
      nil -> {:error, "No connected X account is #{handle}. Connect it in GTM → Social → Post performance."}
      account -> {:ok, account.id}
    end
  end

  def error(:forbidden), do: {:error, "Publishing social posts requires gtm:write."}
  def error(:not_found), do: {:error, "Publication not found."}
  def error(:not_editable), do: {:error, "This publication is publishing or published and can no longer change."}
  def error(:not_cancellable), do: {:error, "Only draft, approved or failed publications can be cancelled."}
  def error(:invalid_scheduled_at), do: {:error, "scheduled_at must be an ISO 8601 date-time with a time zone."}
  def error(:invalid_items), do: {:error, "items must be a list of posts with text and optional media_ids."}
  def error(:media_not_uploaded), do: {:error, "Atlas could not find the uploaded bytes; PUT them to upload_url first."}

  def error({:media_too_large, kind, max}),
    do: {:error, "The #{kind} is empty or larger than #{div(max, 1_000_000)} MB, the most X accepts through Atlas."}

  def error(%Ecto.Changeset{} = changeset), do: {:error, Tool.format_changeset_errors(changeset)}
  def error(reason), do: {:error, inspect(reason)}
end
