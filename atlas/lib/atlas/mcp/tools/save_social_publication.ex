defmodule Atlas.MCP.Tools.SaveSocialPublication do
  @moduledoc """
  Drafts or edits a post or thread for an X account. Agents never approve or
  publish: a person approves the exact revision on the dashboard.
  """

  use Atlas.MCP.Tool,
    name: "save_social_publication",
    schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string", "description" => "Edit this publication. Omit to draft a new one."},
        "account" => %{"type" => "string", "description" => "Connected X account handle, such as @tuistdev."},
        "scheduled_at" => %{
          "type" => "string",
          "format" => "date-time",
          "description" =>
            "When to publish once approved, ISO 8601 with a time zone. A past time publishes on approval."
        },
        "items" => %{
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 25,
          "description" => "The posts in thread order; one item is a single post.",
          "items" => %{
            "type" => "object",
            "required" => ["text"],
            "properties" => %{
              "text" => %{"type" => "string", "description" => "Up to 280 characters; each link counts as 23."},
              "media_ids" => %{
                "type" => "array",
                "maxItems" => 4,
                "items" => %{"type" => "string"},
                "description" =>
                  "Finalized media from create_social_media_upload: up to four images, or one GIF or video."
              }
            },
            "additionalProperties" => false
          }
        },
        "social_post_revision_id" => %{
          "type" => "string",
          "description" => "The social idea revision this publishes, when it came from one."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["publication"],
      "properties" => %{"publication" => Atlas.MCP.Serializers.SocialPublishing.publication_schema()},
      "additionalProperties" => false
    }

  alias Atlas.GTM.SocialPublishing
  alias Atlas.MCP.Serializers.SocialPublishing, as: Serializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "Draft a post or thread for an X account Atlas holds, or edit a draft by `id` (an edit needs re-approval). New drafts need account, scheduled_at and items. Nothing publishes until a person approves this exact revision in Atlas (GTM → Social → Publishing); share the returned dashboard_url with them. Requires gtm:write."

  def execute(conn, args) do
    user = Tool.current_user(conn)

    with :ok <- Tool.authorize_scope(conn, "gtm:write", "Social publishing"),
         {:ok, account_id} <- Serializer.account_id(args["account"]) do
      attrs =
        args
        |> Map.take(["scheduled_at", "items", "social_post_revision_id"])
        |> then(&if(account_id, do: Map.put(&1, "social_account_id", account_id), else: &1))

      result =
        if args["id"], do: SocialPublishing.update(user, args["id"], attrs), else: SocialPublishing.create(user, attrs)

      case result do
        {:ok, publication} -> {:ok, %{publication: Serializer.publication(SocialPublishing.get(publication.id))}}
        {:error, reason} -> Serializer.error(reason)
      end
    end
  end
end
