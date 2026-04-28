defmodule TuistWeb.Orchard.VMController do
  @moduledoc """
  REST API for `Tuist.Orchard.VM`. Mirrors `/v1/vms` from Cirrus's
  upstream Orchard.

  PUT /v1/vms/:name has dual semantics:
    * If the User-Agent starts with `Orchard/0` (legacy worker), the
      request body is interpreted as a state update (status,
      conditions). Same compat shim Cirrus carries for old workers.
    * Otherwise the body is a spec update.

  PUT /v1/vms/:name/state always updates state.
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
      case Orchard.create_vm(params) do
        {:ok, vm} -> json(conn, JSON.render_vm(vm))
        {:error, %Ecto.Changeset{} = cs} -> error(conn, 400, errors(cs))
      end
    end
  end

  def update(conn, %{"name" => name} = params) do
    conn = OrchardAuthPlug.require_role(conn, "compute:write")

    if conn.halted do
      conn
    else
      case Orchard.get_vm_by_name(name) do
        nil ->
          error(conn, 404, "VM not found")

        vm ->
          ua =
            case get_req_header(conn, "user-agent") do
              [v | _] -> v
              _ -> ""
            end

          # Legacy compat: workers running Orchard/0.x still PUT state
          # to this URL instead of /vms/:name/state.
          if String.starts_with?(ua, "Orchard/0") do
            apply_state(conn, vm, params)
          else
            apply_spec(conn, vm, params)
          end
      end
    end
  end

  def update_state(conn, %{"name" => name} = params) do
    conn = OrchardAuthPlug.require_role(conn, "compute:write")

    if conn.halted do
      conn
    else
      case Orchard.get_vm_by_name(name) do
        nil -> error(conn, 404, "VM not found")
        vm -> apply_state(conn, vm, params)
      end
    end
  end

  def show(conn, %{"name" => name}) do
    conn = OrchardAuthPlug.require_role(conn, "compute:read")

    if conn.halted do
      conn
    else
      case Orchard.get_vm_by_name(name) do
        nil -> error(conn, 404, "VM not found")
        vm -> json(conn, JSON.render_vm(vm))
      end
    end
  end

  def index(conn, params) do
    conn = OrchardAuthPlug.require_role(conn, "compute:read")

    if conn.halted do
      conn
    else
      opts = list_opts_from_params(params)
      json(conn, JSON.render_vms(Orchard.list_vms(opts)))
    end
  end

  def delete(conn, %{"name" => name}) do
    conn = OrchardAuthPlug.require_role(conn, "compute:write")

    if conn.halted do
      conn
    else
      case Orchard.get_vm_by_name(name) do
        nil ->
          # Idempotent — same shape as the upstream client treats a
          # delete-of-missing as success.
          send_resp(conn, 204, "")

        vm ->
          {:ok, _} = Orchard.delete_vm(vm)
          send_resp(conn, 204, "")
      end
    end
  end

  defp apply_spec(conn, vm, params) do
    case Orchard.update_vm_spec(vm, params) do
      {:ok, updated} -> json(conn, JSON.render_vm(updated))
      {:error, :terminal_state} -> error(conn, 412, "VM is in a terminal state")
      {:error, %Ecto.Changeset{} = cs} -> error(conn, 400, errors(cs))
    end
  end

  defp apply_state(conn, vm, params) do
    case Orchard.update_vm_state(vm, params) do
      {:ok, updated} -> json(conn, JSON.render_vm(updated))
      {:error, %Ecto.Changeset{} = cs} -> error(conn, 400, errors(cs))
    end
  end

  defp list_opts_from_params(params) do
    case Map.get(params, "filter") do
      "worker=" <> worker -> [worker_name: worker]
      _ -> []
    end
  end

  defp error(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{"message" => to_string(message)})
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
