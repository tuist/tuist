defmodule Atlas.MCP.Tools.PagesSerializers do
  @moduledoc """
  JSON serialization for the Pages MCP tools.
  """

  alias Atlas.Engineering.Pages
  alias Atlas.Engineering.Pages.Deploy
  alias Atlas.Engineering.Pages.Page
  alias Atlas.MCP.Tool
  alias AtlasWeb.Plugs.PagesSubdomain

  def page(%Page{} = page) do
    %{
      "id" => page.id,
      "slug" => page.slug,
      "title" => page.title,
      "description" => page.description,
      "url" => Pages.public_url(page, host_suffix()),
      "dashboard_path" => Pages.dashboard_path(page),
      "current_deploy_id" => page.current_deploy_id,
      "current_deploy" => optional_deploy(page.current_deploy),
      "created_by" => user(page.created_by_user),
      "inserted_at" => Tool.iso8601(page.inserted_at),
      "updated_at" => Tool.iso8601(page.updated_at)
    }
  end

  def deploy(%Deploy{} = deploy) do
    %{
      "id" => deploy.id,
      "page_id" => deploy.page_id,
      "state" => Atom.to_string(deploy.state),
      "file_count" => deploy.file_count,
      "total_bytes" => deploy.total_bytes,
      "finalized_at" => Tool.iso8601(deploy.finalized_at),
      "inserted_at" => Tool.iso8601(deploy.inserted_at)
    }
  end

  def page_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "slug" => %{"type" => "string"},
        "title" => %{"type" => ["string", "null"]},
        "description" => %{"type" => ["string", "null"]},
        "url" => %{"type" => "string"},
        "dashboard_path" => %{"type" => "string"},
        "current_deploy_id" => %{"type" => ["string", "null"]},
        "current_deploy" => %{"type" => ["object", "null"]},
        "created_by" => %{"type" => ["object", "null"]},
        "inserted_at" => %{"type" => ["string", "null"]},
        "updated_at" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "slug", "url", "dashboard_path"],
      "additionalProperties" => false
    }
  end

  def upload_schema do
    %{
      "type" => "object",
      "properties" => %{
        "path" => %{"type" => "string"},
        "upload_url" => %{"type" => "string"},
        "required_headers" => %{"type" => "object"},
        "storage_key" => %{"type" => "string"}
      },
      "required" => ["path", "upload_url", "required_headers"],
      "additionalProperties" => false
    }
  end

  defp optional_deploy(nil), do: nil
  defp optional_deploy(%Ecto.Association.NotLoaded{}), do: nil
  defp optional_deploy(%Deploy{} = d), do: deploy(d)

  defp user(nil), do: nil
  defp user(%Ecto.Association.NotLoaded{}), do: nil

  defp user(user) do
    %{
      "id" => user.id,
      "name" => Map.get(user, :name),
      "email" => Map.get(user, :email)
    }
  end

  defp host_suffix do
    Application.get_env(:atlas, PagesSubdomain, [])
    |> Keyword.get(:host_suffix, "atlas.tuist.dev")
  end
end
