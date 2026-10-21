defmodule AtlasWeb.NativeController do
  use AtlasWeb, :controller

  alias Atlas.Accounts
  alias Atlas.Audit
  alias Atlas.Finance.Invoices
  alias Atlas.Native
  alias Atlas.Tasks
  alias Atlas.Users

  plug :authorize when action != :profile

  def action(conn, _opts) do
    Audit.with_context(Audit.context_from_conn(conn, "api"), fn ->
      apply(__MODULE__, action_name(conn), [conn, conn.params])
    end)
  rescue
    Ecto.ConstraintError -> error(conn, :conflict, "resource_conflict")
    Ecto.StaleEntryError -> error(conn, :conflict, "resource_conflict")
  end

  def profile(conn, _params) do
    user = conn.assigns.current_user

    json(conn, %{
      server_version: to_string(Application.spec(:atlas, :vsn)),
      user: %{name: user.name || "", email: user.email}
    })
  end

  def index(conn, _params) do
    case Native.list(resource(conn), conn.query_params, conn.assigns.current_user) do
      {:ok, page} -> json(conn, page)
      {:error, reason} -> respond(conn, {:error, reason})
    end
  end

  def show(conn, %{"id" => id}), do: respond(conn, Native.get(resource(conn), id))

  def create(conn, params) do
    case attributes(conn, params) do
      {:ok, attrs} ->
        user = conn.assigns.current_user

        result =
          case resource(conn) do
            "tasks" ->
              attrs = if attrs["assignee_id"] in [nil, ""], do: Map.put(attrs, "assignee_id", user.id), else: attrs
              Tasks.create_task(attrs, user, interface: "api")

            "accounts" ->
              Accounts.create_manual_account(attrs)

            "invoices" ->
              Invoices.create_manual_invoice(attrs, user, interface: "api")
          end

        respond(conn, result, :created)

      error ->
        respond(conn, error)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, item} <- Native.get(resource(conn), id),
         {:ok, attrs} <- attributes(conn, params) do
      user = conn.assigns.current_user

      result =
        case resource(conn) do
          "tasks" -> Tasks.update_task(item, attrs, user, interface: "api")
          "accounts" -> Accounts.update_account(item, attrs)
          "invoices" -> Invoices.update_manual_invoice(id, attrs, user, interface: "api")
        end

      respond(conn, result)
    else
      error -> respond(conn, error)
    end
  end

  def delete(conn, %{"id" => id}) do
    case Native.get(resource(conn), id) do
      {:ok, item} ->
        user = conn.assigns.current_user

        result =
          case resource(conn) do
            "tasks" -> Tasks.delete_task(item, user, interface: "api")
            "accounts" -> Accounts.delete_account(item)
            "invoices" -> Invoices.delete_manual_invoice(id, user, interface: "api")
          end

        case result do
          {:ok, _item} -> json(conn, %{deleted: true})
          error -> respond(conn, error)
        end

      error ->
        respond(conn, error)
    end
  end

  def complete(conn, %{"id" => id}) do
    if resource(conn) == "tasks" do
      case Native.get("tasks", id) do
        {:ok, task} -> respond(conn, Tasks.complete_task(task, conn.assigns.current_user, interface: "api"))
        error -> respond(conn, error)
      end
    else
      error(conn, :not_found, "not_found")
    end
  end

  defp resource(conn), do: conn.path_params["resource"]

  defp authorize(conn, _opts) do
    action = if action_name(conn) in [:index, :show], do: "read", else: "write"

    allowed =
      case resource(conn) do
        "tasks" -> true
        "accounts" -> Users.has_scope?(conn.assigns.current_user, "accounts:#{action}")
        "invoices" -> Users.has_scope?(conn.assigns.current_user, "finance:#{action}")
        _unknown -> :not_found
      end

    case allowed do
      true -> conn
      false -> conn |> error(:forbidden, "forbidden") |> halt()
      :not_found -> conn |> error(:not_found, "not_found") |> halt()
    end
  end

  defp attributes(conn, params) do
    attrs = Map.take(params, Enum.map(Native.fields(resource(conn)), &to_string/1))

    if Enum.all?(attrs, fn {_key, value} -> is_binary(value) end),
      do: {:ok, attrs},
      else: {:error, :invalid_params}
  end

  defp respond(conn, result, status \\ :ok)

  defp respond(conn, {:ok, item}, status),
    do: conn |> put_status(status) |> json(%{item: Native.record(resource(conn), item, conn.assigns.current_user)})

  defp respond(conn, {:error, %Ecto.Changeset{} = changeset}, _status) do
    conflict? =
      Enum.any?(changeset.errors, fn {_field, {_message, opts}} ->
        opts[:constraint] in [:unique, :foreign, :no_assoc]
      end)

    status = if conflict?, do: :conflict, else: :unprocessable_entity
    fields = Ecto.Changeset.traverse_errors(changeset, fn {_message, _opts} -> "invalid" end)
    conn |> put_status(status) |> json(%{error: "validation_failed", fields: fields})
  end

  defp respond(conn, {:error, :not_found}, _status), do: error(conn, :not_found, "not_found")
  defp respond(conn, {:error, :read_only}, _status), do: error(conn, :forbidden, "read_only")
  defp respond(conn, {:error, :invalid_params}, _status), do: error(conn, :unprocessable_entity, "invalid_params")
  defp respond(conn, {:error, _reason}, _status), do: error(conn, :conflict, "resource_conflict")

  defp error(conn, status, message), do: conn |> put_status(status) |> json(%{error: message})
end
