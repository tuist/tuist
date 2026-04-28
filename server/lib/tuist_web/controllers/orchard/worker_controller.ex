defmodule TuistWeb.Orchard.WorkerController do
  @moduledoc """
  REST API for `Tuist.Orchard.Worker`. Mirrors Cirrus's
  `/v1/workers` endpoints; auth is handled by
  `TuistWeb.Plugs.OrchardAuthPlug` in the router.
  """
  use TuistWeb, :controller

  alias Tuist.Orchard
  alias TuistWeb.Orchard.JSON
  alias TuistWeb.Plugs.OrchardAuthPlug

  def create(conn, params) do
    conn = OrchardAuthPlug.require_role(conn, "compute:write")

    if conn.halted do
      conn
    else
      case Orchard.register_worker(params) do
        {:ok, worker} -> json(conn, JSON.render_worker(worker))
        {:error, :machine_id_conflict} -> error(conn, 409, "machine_id conflict")
        {:error, changeset} -> error(conn, 400, changeset_errors(changeset))
      end
    end
  end

  def update(conn, %{"name" => name} = params) do
    conn = OrchardAuthPlug.require_role(conn, "compute:write")

    if conn.halted do
      conn
    else
      case Orchard.get_worker_by_name(name) do
        nil ->
          error(conn, 404, "worker not found")

        worker ->
          case Orchard.heartbeat_worker(worker, params) do
            {:ok, w} -> json(conn, JSON.render_worker(w))
            {:error, changeset} -> error(conn, 400, changeset_errors(changeset))
          end
      end
    end
  end

  def show(conn, %{"name" => name}) do
    conn = OrchardAuthPlug.require_role(conn, "compute:read")

    if conn.halted do
      conn
    else
      case Orchard.get_worker_by_name(name) do
        nil -> error(conn, 404, "worker not found")
        worker -> json(conn, JSON.render_worker(worker))
      end
    end
  end

  def index(conn, _params) do
    conn = OrchardAuthPlug.require_role(conn, "compute:read")

    if conn.halted do
      conn
    else
      json(conn, JSON.render_workers(Orchard.list_workers()))
    end
  end

  def delete(conn, %{"name" => name}) do
    conn = OrchardAuthPlug.require_role(conn, "compute:write")

    if conn.halted do
      conn
    else
      case Orchard.get_worker_by_name(name) do
        nil ->
          error(conn, 404, "worker not found")

        worker ->
          {:ok, _} = Orchard.delete_worker(worker)
          send_resp(conn, 204, "")
      end
    end
  end

  defp error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{"message" => to_string(message)})
  end

  defp changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Jason.encode!()
  end
end
