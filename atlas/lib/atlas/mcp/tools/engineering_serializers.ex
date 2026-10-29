defmodule Atlas.MCP.Tools.EngineeringSerializers do
  @moduledoc """
  Shared JSON serialization helpers for the Engineering MCP tools
  (projects, domains, repositories, webhooks, DSN keys). Keeps output
  shape consistent across the read and write surfaces.
  """

  alias Atlas.Engineering.Errors
  alias AtlasWeb.Endpoint

  def project(project) do
    %{
      "id" => project.id,
      "name" => project.name,
      "description" => project.description,
      "visibility" => to_string(project.visibility),
      "domain_ids" => Enum.map(project.domains || [], & &1.id),
      "repositories" => Enum.map(project.github_repositories || [], fn r -> "#{r.owner}/#{r.name}" end)
    }
  end

  def domain(domain) do
    %{
      "id" => domain.id,
      "name" => domain.name,
      "description" => domain.description,
      "visibility" => to_string(domain.visibility),
      "project_ids" => Enum.map(domain.projects || [], & &1.id)
    }
  end

  def repository(repository) do
    %{
      "id" => repository.id,
      "owner" => repository.owner,
      "name" => repository.name,
      "visibility" => to_string(repository.visibility || "public")
    }
  end

  def webhook(webhook) do
    %{
      "id" => webhook.id,
      "name" => webhook.name,
      "source" => to_string(webhook.source),
      "last_used_at" => webhook.last_used_at && DateTime.to_iso8601(webhook.last_used_at),
      "inserted_at" => webhook.inserted_at && DateTime.to_iso8601(webhook.inserted_at)
    }
  end

  def project_key(key), do: stringify(Errors.serialize_project_key(key, Endpoint.url()))

  def webhook_ingest_url(project_id, source, token) do
    Endpoint.url() <> "/webhooks/projects/#{project_id}/#{source}/#{token}"
  end

  defp stringify(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
