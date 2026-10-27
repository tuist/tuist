defmodule Atlas.MCP.Serializers.Moodboard do
  @moduledoc false

  alias Atlas.MCP.Tool

  def attributes do
    %{
      "title" => %{"type" => "string", "minLength" => 1, "maxLength" => 200},
      "url" => %{
        "type" => ["string", "null"],
        "maxLength" => 2048,
        "description" => "Public HTTPS resource URL. Omit for a text resource with content."
      },
      "content" => %{
        "type" => ["string", "null"],
        "maxLength" => 20_000,
        "description" => "Original text, quote, or an excerpt. Required when there is no URL."
      },
      "description" => %{
        "type" => ["string", "null"],
        "maxLength" => 2000,
        "description" => "Why this is worth saving."
      },
      "image_url" => %{
        "type" => ["string", "null"],
        "maxLength" => 2048,
        "description" =>
          "Optional public HTTPS image override. Otherwise Atlas discovers image/video previews in the background."
      },
      "tags" => %{
        "type" => "array",
        "maxItems" => 10,
        "items" => %{"type" => "string", "maxLength" => 40}
      }
    }
  end

  def resource_schema do
    %{
      "type" => "object",
      "properties" =>
        Map.merge(attributes(), %{
          "id" => %{"type" => "string"},
          "kind" => %{"type" => "string"},
          "preview_status" => %{"type" => "string"},
          "preview_image_url" => %{"type" => ["string", "null"]},
          "preview_video_url" => %{"type" => ["string", "null"]},
          "source_title" => %{"type" => ["string", "null"]},
          "source_description" => %{"type" => ["string", "null"]},
          "source_text" => %{"type" => ["string", "null"]},
          "created_by_id" => %{"type" => ["string", "null"]},
          "created_by_name" => %{"type" => ["string", "null"]},
          "inserted_at" => %{"type" => "string"},
          "updated_at" => %{"type" => "string"}
        }),
      "required" =>
        ~w(id title url content kind description image_url tags created_by_id created_by_name inserted_at updated_at preview_status preview_image_url preview_video_url source_title source_description source_text),
      "additionalProperties" => false
    }
  end

  def resource_summary_schema do
    full = resource_schema()
    fields = ~w(content source_text)

    full
    |> Map.put(
      "properties",
      full["properties"]
      |> Map.drop(fields)
      |> Map.merge(%{
        "excerpt" => %{"type" => "string", "maxLength" => 280},
        "has_full_text" => %{"type" => "boolean"}
      })
    )
    |> Map.put("required", (full["required"] -- fields) ++ ~w(excerpt has_full_text))
  end

  def resource_summary(resource) do
    resource(resource)
    |> Map.drop([:content, :source_text])
    |> Map.put(:description, truncate(resource.description, 500))
    |> Map.put(:source_description, truncate(resource.source_description, 500))
    |> Map.put(:excerpt, String.slice(resource.content || resource.source_text || "", 0, 280))
    |> Map.put(:has_full_text, resource.content not in [nil, ""] or resource.source_text not in [nil, ""])
  end

  defp truncate(nil, _limit), do: nil
  defp truncate(value, limit), do: String.slice(value, 0, limit)

  def response_schema do
    %{
      "type" => "object",
      "properties" => %{"resource" => resource_schema()},
      "required" => ["resource"],
      "additionalProperties" => false
    }
  end

  def resource(resource) do
    %{
      id: resource.id,
      title: resource.title,
      url: resource.url,
      content: resource.content,
      kind: resource.kind,
      preview_status: resource.preview_status,
      preview_image_url: resource.preview_image_url,
      preview_video_url: resource.preview_video_url,
      source_title: resource.source_title,
      source_description: resource.source_description,
      source_text: resource.source_text,
      description: resource.description,
      image_url: resource.image_url,
      tags: resource.tags,
      created_by_id: resource.created_by_id,
      created_by_name: resource.created_by && resource.created_by.name,
      inserted_at: resource.inserted_at,
      updated_at: resource.updated_at
    }
  end

  def comment_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "resource_id" => %{"type" => "string"},
        "body" => %{"type" => "string"},
        "author_id" => %{"type" => ["string", "null"]},
        "author_name" => %{"type" => ["string", "null"]},
        "inserted_at" => %{"type" => "string"}
      },
      "required" => ~w(id resource_id body author_id author_name inserted_at),
      "additionalProperties" => false
    }
  end

  def comment(comment) do
    %{
      id: comment.id,
      resource_id: comment.resource_id,
      body: comment.body,
      author_id: comment.author_id,
      author_name: comment.author && comment.author.name,
      inserted_at: comment.inserted_at
    }
  end

  def error(%Ecto.Changeset{} = changeset), do: Tool.format_changeset_errors(changeset)
  def error(:not_found), do: "Resource not found."
  def error(:forbidden), do: "Only the contributor can change or remove this resource."
  def error(:authentication_required), do: "Moodboard requires an authenticated user."
  def error(:capture_conflict), do: "This request ID was already used with different fields."
  def error(:invalid_capture), do: "Provide a valid capture UUID and Moodboard fields."
  def error(:rate_limited), do: "Too many suggestions. Retry later or save without suggestions."
end
