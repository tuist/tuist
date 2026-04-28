defmodule TuistWeb.Orchard.ServiceAccountController do
  @moduledoc """
  CRUD for Orchard service accounts. Requires `admin:write` for
  mutating endpoints, `admin:read` for reads.

  The freshly-created token is returned in the response body of
  POST/PUT exactly once — same one-time-secret pattern Cirrus uses.
  Subsequent GETs only return name + roles.
  """
  use TuistWeb, :controller

  alias Tuist.Orchard
  alias TuistWeb.Orchard.JSON
  alias TuistWeb.Plugs.OrchardAuthPlug

  def create(conn, params) do
    conn = OrchardAuthPlug.require_role(conn, "admin:write")

    if conn.halted do
      conn
    else
      token = generate_token()
      attrs = Map.put(params, "token", token)

      case Orchard.create_service_account(attrs) do
        {:ok, account} ->
          json(conn, JSON.render_service_account(account, include_token: token))

        {:error, %Ecto.Changeset{} = cs} ->
          conn |> put_status(400) |> json(%{"message" => errors(cs)})
      end
    end
  end

  def update(conn, %{"name" => name} = params) do
    conn = OrchardAuthPlug.require_role(conn, "admin:write")

    if conn.halted do
      conn
    else
      case Orchard.get_service_account_by_name(name) do
        nil ->
          conn |> put_status(404) |> json(%{"message" => "service account not found"})

        account ->
          {token, attrs} =
            case Map.get(params, "token") do
              nil ->
                # Generate a fresh token on every update — Cirrus's
                # convention is "PUT rotates."
                t = generate_token()
                {t, Map.put(params, "token", t)}

              t when is_binary(t) ->
                {t, params}
            end

          case Orchard.update_service_account(account, attrs) do
            {:ok, updated} ->
              json(conn, JSON.render_service_account(updated, include_token: token))

            {:error, %Ecto.Changeset{} = cs} ->
              conn |> put_status(400) |> json(%{"message" => errors(cs)})
          end
      end
    end
  end

  def show(conn, %{"name" => name}) do
    conn = OrchardAuthPlug.require_role(conn, "admin:read")

    if conn.halted do
      conn
    else
      case Orchard.get_service_account_by_name(name) do
        nil ->
          conn |> put_status(404) |> json(%{"message" => "service account not found"})

        account ->
          json(conn, JSON.render_service_account(account))
      end
    end
  end

  def index(conn, _params) do
    conn = OrchardAuthPlug.require_role(conn, "admin:read")

    if conn.halted do
      conn
    else
      json(conn, JSON.render_service_accounts(Orchard.list_service_accounts()))
    end
  end

  def delete(conn, %{"name" => name}) do
    conn = OrchardAuthPlug.require_role(conn, "admin:write")

    if conn.halted do
      conn
    else
      case Orchard.get_service_account_by_name(name) do
        nil ->
          send_resp(conn, 204, "")

        account ->
          {:ok, _} = Orchard.delete_service_account(account)
          send_resp(conn, 204, "")
      end
    end
  end

  defp generate_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Jason.encode!()
  end
end
