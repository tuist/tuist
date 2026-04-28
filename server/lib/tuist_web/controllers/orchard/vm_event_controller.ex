defmodule TuistWeb.Orchard.VMEventController do
  @moduledoc """
  Per-VM event stream. Workers POST batches of log/condition/status
  events; clients (`kubectl logs`, `orchard logs`) GET them with
  `?since=N` to resume after disconnect.
  """
  use TuistWeb, :controller

  alias Tuist.Orchard
  alias TuistWeb.Orchard.JSON
  alias TuistWeb.Plugs.OrchardAuthPlug

  def append(conn, %{"name" => name} = params) do
    conn = OrchardAuthPlug.require_role(conn, "compute:write")

    if conn.halted do
      conn
    else
      events = Map.get(params, "events", [])

      case Orchard.append_vm_events(name, events) do
        {:ok, inserted} ->
          json(conn, %{"appended" => length(inserted)})

        {:error, _changeset} ->
          conn |> put_status(400) |> json(%{"message" => "invalid event payload"})
      end
    end
  end

  def index(conn, %{"name" => name} = params) do
    conn = OrchardAuthPlug.require_role(conn, "compute:read")

    if conn.halted do
      conn
    else
      since =
        case Integer.parse(Map.get(params, "since", "0")) do
          {n, _} -> n
          :error -> 0
        end

      limit =
        case Integer.parse(Map.get(params, "limit", "1000")) do
          {n, _} when n > 0 and n <= 10_000 -> n
          _ -> 1_000
        end

      events = Orchard.list_vm_events(name, since: since, limit: limit)
      json(conn, JSON.render_vm_events(events))
    end
  end
end
