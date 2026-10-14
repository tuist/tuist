defmodule TuistWeb.Plugs.ReportActorPlug do
  @moduledoc """
  Captures an optional report claim after normal authentication and authorization.
  Identity links and provenance are derived exclusively from server state.
  """

  import Plug.Conn

  alias Tuist.ReportActor
  alias TuistWeb.Authentication

  def init(opts), do: opts

  def call(conn, _opts) do
    if Authentication.authenticated?(conn) do
      user = Authentication.attributed_user(conn)

      assign(conn, :report_actor, %{
        actor_account_id: if(user, do: user.account.id, else: 0),
        claimed_actor_id: claimed_identifier(conn),
        submission_auth: "token"
      })
    else
      conn |> send_resp(:unauthorized, "Authentication required") |> halt()
    end
  end

  def actor(conn) do
    user = Authentication.attributed_user(conn)

    conn
    |> ReportActor.attributes()
    |> Map.put(:actor_account, if(user, do: user.account))
    |> ReportActor.actor()
  end

  defp claimed_identifier(conn) do
    case get_req_header(conn, "x-tuist-actor-id") do
      [identifier] -> if ReportActor.valid_identifier?(identifier), do: identifier, else: ""
      _ -> ""
    end
  end
end
