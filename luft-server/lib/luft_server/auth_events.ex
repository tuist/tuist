defmodule LuftServer.AuthEvents do
  @moduledoc """
  One log line per authentication event: sign-in, sign-out, native code
  exchange and refresh, refresh retry and reuse, and session revocation.

  Responses alone cannot tell these apart (a forged state and a replayed
  refresh token are both a bare 400), so each line names the event, its
  outcome, the Tuist subject and the Luft session it concerns, and the client.
  Where the request came from is already in the request's Logger metadata
  (`LuftServerWeb.Plugs.ClientContext`). Lines go to stdout like the rest of
  the server's logs, which the cluster's log collector ships to Pulse.

  Only identifiers are logged, never tokens, codes, verifiers or the session
  cookie: callers pass a session or a session ID, not a credential.
  """
  require Logger

  alias LuftServer.Sessions.Session

  @doc """
  Logs `event` with `outcome`. `opts` takes `:client` and `:session`, a
  `Session`, whose ID and Tuist subject are logged, or a session ID.
  """
  def log(event, outcome, opts \\ []) do
    metadata =
      [auth_event: event, auth_outcome: outcome, auth_client: opts[:client]] ++
        session_metadata(opts[:session])

    Logger.log(level(outcome), "auth #{event} #{outcome}", metadata)
  end

  defp session_metadata(%Session{id: id, user_sub: sub}), do: [session_id: id, user_sub: sub]
  defp session_metadata(id) when is_binary(id), do: [session_id: id]
  defp session_metadata(nil), do: []

  defp level(outcome) when outcome in [:success, :retried], do: :info
  defp level(_outcome), do: :warning
end
