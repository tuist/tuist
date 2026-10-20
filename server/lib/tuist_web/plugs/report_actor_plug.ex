defmodule TuistWeb.Plugs.ReportActorPlug do
  @moduledoc """
  Reads the backwards-compatible actor header on report creation only. All
  identity links and publishing provenance are derived from server state.
  """
  use TuistWeb, :controller

  alias Tuist.ReportActor
  alias TuistWeb.Authentication

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "x-tuist-actor-id") do
      [] ->
        assign_actor(conn, "")

      [identifier] ->
        if ReportActor.valid_identifier?(identifier) do
          assign_actor(conn, identifier)
        else
          discard_claim(conn)
        end

      _ ->
        discard_claim(conn)
    end
  end

  defp assign_actor(conn, identifier) do
    actor_account_id =
      case Authentication.attributed_user(conn) do
        nil -> 0
        user -> user.account.id
      end

    assign(conn, :report_actor, %{
      actor_account_id: actor_account_id,
      claimed_actor_id: identifier,
      submission_auth: if(Authentication.authenticated?(conn), do: "token", else: "network_trusted")
    })
  end

  defp discard_claim(conn) do
    Logger.warning("Ignoring invalid or duplicated optional x-tuist-actor-id header")
    assign_actor(conn, "")
  end
end
