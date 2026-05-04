defmodule TuistWeb.SCIM.UsersController do
  @moduledoc """
  SCIM 2.0 `/Users` endpoints (RFC 7644 §3).
  """
  use TuistWeb, :controller

  import TuistWeb.SCIM.Helpers

  alias Tuist.SCIM
  alias Tuist.SCIM.Filter
  alias Tuist.SCIM.Resource

  def index(conn, params) do
    organization = conn.assigns.scim_organization
    base_url = conn.assigns.scim_base_url

    filter = Filter.parse(Map.get(params, "filter"))

    if filter == :error do
      send_scim_error(conn, 400, "Unsupported filter expression", "invalidFilter")
    else
      case SCIM.list_users(organization,
             filter: filter,
             start_index: parse_int(Map.get(params, "startIndex"), 1),
             count: parse_int(Map.get(params, "count"), 100)
           ) do
        {:ok, page} ->
          resources = Enum.map(page.users, &Resource.render_user(&1, base_url))
          send_scim_json(conn, 200, Resource.render_list(resources, page))

        {:error, :unsupported_filter} ->
          send_scim_error(conn, 400, "Unsupported filter attribute", "invalidFilter")
      end
    end
  end

  def show(conn, %{"id" => id}) do
    organization = conn.assigns.scim_organization
    base_url = conn.assigns.scim_base_url

    case SCIM.get_user(organization, id) do
      {:ok, user} -> send_scim_json(conn, 200, Resource.render_user(user, base_url))
      {:error, :not_found} -> send_scim_error(conn, 404, "User not found")
    end
  end

  def create(conn, params) do
    organization = conn.assigns.scim_organization
    base_url = conn.assigns.scim_base_url

    with {:ok, attrs} <- parse_user_attrs(params),
         {:ok, user} <- SCIM.provision_user(organization, attrs) do
      conn
      |> put_resp_header("location", "#{base_url}/Users/#{user.id}")
      |> send_scim_json(201, Resource.render_user(user, base_url))
    else
      {:error, :missing_user_name} ->
        send_scim_error(conn, 400, "userName is required", "invalidValue")

      {:error, :invalid_email} ->
        send_scim_error(conn, 400, "userName must be a valid email address", "invalidValue")

      {:error, :email_taken} ->
        send_scim_error(conn, 409, "User already exists", "uniqueness")

      {:error, %Ecto.Changeset{} = changeset} ->
        send_scim_error(conn, 400, format_changeset(changeset), "invalidValue")

      {:error, _other} ->
        send_scim_error(conn, 500, "Could not provision user")
    end
  end

  def replace(conn, %{"id" => id} = params) do
    organization = conn.assigns.scim_organization
    base_url = conn.assigns.scim_base_url

    with {:ok, attrs} <- parse_user_attrs(params, require_user_name: false),
         {:ok, user} <- SCIM.replace_user(organization, id, attrs) do
      send_scim_json(conn, 200, Resource.render_user(user, base_url))
    else
      {:error, :not_found} -> send_scim_error(conn, 404, "User not found")
      {:error, :invalid_email} -> send_scim_error(conn, 400, "userName must be a valid email", "invalidValue")
      {:error, :email_taken} -> send_scim_error(conn, 409, "User already exists", "uniqueness")
      {:error, %Ecto.Changeset{} = c} -> send_scim_error(conn, 400, format_changeset(c), "invalidValue")
      {:error, _} -> send_scim_error(conn, 500, "Could not replace user")
    end
  end

  def patch(conn, %{"id" => id} = params) do
    organization = conn.assigns.scim_organization
    base_url = conn.assigns.scim_base_url
    ops = Map.get(params, "Operations", [])

    case SCIM.patch_user(organization, id, ops) do
      {:ok, user} -> send_scim_json(conn, 200, Resource.render_user(user, base_url))
      {:error, :not_found} -> send_scim_error(conn, 404, "User not found")
      {:error, :email_taken} -> send_scim_error(conn, 409, "User already exists", "uniqueness")
      {:error, %Ecto.Changeset{} = c} -> send_scim_error(conn, 400, format_changeset(c), "invalidValue")
      {:error, _} -> send_scim_error(conn, 500, "Could not patch user")
    end
  end

  def delete(conn, %{"id" => id}) do
    organization = conn.assigns.scim_organization

    case SCIM.deactivate_user(organization, id) do
      {:ok, _user} -> send_resp(conn, 204, "")
      {:error, :not_found} -> send_scim_error(conn, 404, "User not found")
      {:error, _} -> send_scim_error(conn, 500, "Could not deactivate user")
    end
  end

  defp parse_user_attrs(params, opts \\ []) do
    require_user_name = Keyword.get(opts, :require_user_name, true)

    user_name = Map.get(params, "userName")

    cond do
      require_user_name and (is_nil(user_name) or user_name == "") ->
        {:error, :missing_user_name}

      not is_nil(user_name) and not Tuist.Accounts.User.email_valid?(user_name) ->
        {:error, :invalid_email}

      true ->
        attrs =
          %{}
          |> maybe_put(:user_name, user_name)
          |> maybe_put(:active, Map.get(params, "active"))
          |> maybe_put(:role, role_from_payload(params))

        {:ok, attrs}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp role_from_payload(params) do
    case Map.get(params, "roles") do
      [%{"value" => v} | _] when is_binary(v) -> v
      [v | _] when is_binary(v) -> v
      _ -> nil
    end
  end

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      _ -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(_, default), do: default

  defp format_changeset(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&format_error/1)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  defp format_error({message, opts}) do
    Regex.replace(~r"%{(\w+)}", message, fn _, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end
end
