defmodule Atlas.MCP.Tools.SpecSerializers do
  @moduledoc """
  Shared JSON serialization helpers for the spec MCP tools.
  """

  alias Atlas.Engineering.Specs.Comment
  alias Atlas.Engineering.Specs.Revision
  alias Atlas.Engineering.Specs.Spec
  alias Atlas.MCP.Tool

  def spec(%Spec{} = spec) do
    %{
      "id" => spec.id,
      "number" => spec.number,
      "title" => spec.title,
      "body" => spec.body,
      "summary" => spec.summary,
      "status" => Atom.to_string(spec.status),
      "visibility" => Atom.to_string(spec.visibility),
      "revision" => spec.lock_version,
      "engineering_project" => engineering_project(spec),
      "author" => author(spec),
      "domains" => domains(spec),
      "comments" => comments(spec),
      "revisions" => revisions(spec),
      "inserted_at" => Tool.iso8601(spec.inserted_at),
      "updated_at" => Tool.iso8601(spec.updated_at),
      "path" => spec.number && "/engineering/specs/#{spec.number}"
    }
  end

  def comment(%Comment{} = comment) do
    %{
      "id" => comment.id,
      "spec_id" => comment.spec_id,
      "body" => comment.body,
      "author" => comment_author(comment),
      "inserted_at" => Tool.iso8601(comment.inserted_at),
      "updated_at" => Tool.iso8601(comment.updated_at)
    }
  end

  def comments(%Spec{} = spec) do
    Enum.map((Ecto.assoc_loaded?(spec.comments) && spec.comments) || [], &comment/1)
  end

  def revisions(%Spec{} = spec) do
    Enum.map(
      (Ecto.assoc_loaded?(spec.revisions) && spec.revisions) || [],
      &revision/1
    )
  end

  defp revision(%Revision{} = revision) do
    %{
      "revision" => revision.revision,
      "title" => revision.title,
      "body" => revision.body,
      "summary" => revision.summary,
      "status" => Atom.to_string(revision.status),
      "author" => revision_author(revision),
      "inserted_at" => Tool.iso8601(revision.inserted_at)
    }
  end

  defp engineering_project(%{engineering_project: project}) do
    if Ecto.assoc_loaded?(project) and not is_nil(project) do
      %{
        "id" => project.id,
        "name" => project.name,
        "visibility" => Atom.to_string(project.visibility)
      }
    end
  end

  defp author(%{created_by_user: user}) do
    if Ecto.assoc_loaded?(user) and not is_nil(user) do
      %{"id" => user.id, "email" => user.email, "name" => user.name}
    end
  end

  defp domains(%{domains: domains}) do
    Enum.map((Ecto.assoc_loaded?(domains) && domains) || [], fn domain ->
      %{"id" => domain.id, "name" => domain.name, "visibility" => Atom.to_string(domain.visibility)}
    end)
  end

  defp comment_author(%{user: %{email: email}}) when is_binary(email), do: email
  defp comment_author(%{author_name: name}) when is_binary(name), do: name
  defp comment_author(_comment), do: "Anonymous"

  defp revision_author(%{user: %{email: email}}) when is_binary(email), do: email
  defp revision_author(_revision), do: nil

  @doc "JSON schema fragment for a spec returned by MCP tools."
  def spec_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "number" => %{"type" => ["integer", "null"]},
        "title" => %{"type" => "string"},
        "body" => %{"type" => "string"},
        "summary" => %{"type" => ["string", "null"]},
        "status" => %{"type" => "string"},
        "visibility" => %{"type" => "string"},
        "revision" => %{"type" => "integer"},
        "engineering_project" => %{"type" => ["object", "null"]},
        "author" => %{"type" => ["object", "null"]},
        "domains" => %{"type" => "array", "items" => %{"type" => "object"}},
        "comments" => %{"type" => "array", "items" => comment_schema()},
        "revisions" => %{"type" => "array", "items" => %{"type" => "object"}},
        "inserted_at" => %{"type" => ["string", "null"]},
        "updated_at" => %{"type" => ["string", "null"]},
        "path" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "id",
        "number",
        "title",
        "body",
        "summary",
        "status",
        "visibility",
        "revision",
        "engineering_project",
        "author",
        "domains",
        "comments",
        "revisions",
        "inserted_at",
        "updated_at",
        "path"
      ],
      "additionalProperties" => false
    }
  end

  @doc "JSON schema fragment for a spec comment returned by MCP tools."
  def comment_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "spec_id" => %{"type" => "string"},
        "body" => %{"type" => "string"},
        "author" => %{"type" => "string"},
        "inserted_at" => %{"type" => ["string", "null"]},
        "updated_at" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "spec_id", "body", "author", "inserted_at", "updated_at"],
      "additionalProperties" => false
    }
  end
end
