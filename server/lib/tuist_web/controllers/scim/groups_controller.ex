defmodule TuistWeb.SCIM.GroupsController do
  @moduledoc """
  SCIM 2.0 `/Groups` endpoints. Tuist exposes two synthetic groups per
  organization: "Admins" and "Users", mapping to the existing role hierarchy.
  """
  use TuistWeb, :controller

  import TuistWeb.SCIM.Helpers

  alias Tuist.SCIM
  alias Tuist.SCIM.Resource

  def index(conn, _params) do
    organization = conn.assigns.scim_organization
    base_url = conn.assigns.scim_base_url

    groups = SCIM.list_groups(organization)
    resources = Enum.map(groups, &Resource.render_group(&1, base_url))

    page = %{total: length(resources), start_index: 1}
    send_scim_json(conn, 200, Resource.render_list(resources, page))
  end

  def show(conn, %{"id" => id}) do
    organization = conn.assigns.scim_organization
    base_url = conn.assigns.scim_base_url

    case SCIM.get_group(organization, id) do
      {:ok, group} -> send_scim_json(conn, 200, Resource.render_group(group, base_url))
      {:error, :not_found} -> send_scim_error(conn, 404, "Group not found")
    end
  end

  def patch(conn, %{"id" => id} = params) do
    organization = conn.assigns.scim_organization
    base_url = conn.assigns.scim_base_url
    ops = Map.get(params, "Operations", [])

    case SCIM.patch_group(organization, id, ops) do
      {:ok, group} -> send_scim_json(conn, 200, Resource.render_group(group, base_url))
      {:error, :not_found} -> send_scim_error(conn, 404, "Group not found")
    end
  end
end
