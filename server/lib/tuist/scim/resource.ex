defmodule Tuist.SCIM.Resource do
  @moduledoc """
  Encoders that map Tuist domain structs to SCIM 2.0 JSON resources
  (RFC 7643).
  """
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User

  @user_schema "urn:ietf:params:scim:schemas:core:2.0:User"
  @group_schema "urn:ietf:params:scim:schemas:core:2.0:Group"
  @list_schema "urn:ietf:params:scim:api:messages:2.0:ListResponse"

  def user_schema, do: @user_schema
  def group_schema, do: @group_schema
  def list_schema, do: @list_schema

  def render_user(%User{} = user, base_url) do
    handle =
      case user do
        %User{account: %Account{name: name}} -> name
        _ -> user.email
      end

    %{
      schemas: [@user_schema],
      id: to_string(user.id),
      userName: user.email,
      displayName: handle,
      active: user.active,
      emails: [%{value: user.email, primary: true, type: "work"}],
      meta: %{
        resourceType: "User",
        location: "#{base_url}/Users/#{user.id}",
        created: format_dt(inserted_at(user)),
        lastModified: format_dt(updated_at(user))
      }
    }
  end

  def render_group(%{id: id, display_name: display_name, members: members}, base_url) do
    %{
      schemas: [@group_schema],
      id: id,
      displayName: display_name,
      members:
        Enum.map(members, fn user ->
          %{
            value: to_string(user.id),
            display: member_display(user),
            "$ref": "#{base_url}/Users/#{user.id}"
          }
        end),
      meta: %{
        resourceType: "Group",
        location: "#{base_url}/Groups/#{id}"
      }
    }
  end

  def render_list(resources, %{total: total, start_index: start_index}) do
    %{
      schemas: [@list_schema],
      totalResults: total,
      startIndex: start_index,
      itemsPerPage: length(resources),
      Resources: resources
    }
  end

  def render_error(status, detail, scim_type \\ nil) do
    base = %{
      schemas: ["urn:ietf:params:scim:api:messages:2.0:Error"],
      status: Integer.to_string(status),
      detail: detail
    }

    if scim_type, do: Map.put(base, :scimType, scim_type), else: base
  end

  defp member_display(%User{} = user) do
    case user do
      %User{account: %Account{name: name}} -> name
      _ -> user.email
    end
  end

  def inserted_at(%User{} = user), do: Map.get(user, :created_at) || Map.get(user, :inserted_at)

  defp updated_at(%User{} = user), do: Map.get(user, :updated_at) || inserted_at(user)

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt) <> "Z"
end
