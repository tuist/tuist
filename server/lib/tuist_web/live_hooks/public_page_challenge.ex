defmodule TuistWeb.LiveHooks.PublicPageChallenge do
  @moduledoc ~S"""
  LiveView on_mount hook paired with
  `TuistWeb.Plugs.PublicPageChallengePlug`. Runs at the connected
  mount so a client that opens a LiveSocket directly (bypassing the
  dead-render Plug pipeline) still gets challenged before any
  dashboard query fires.

  The freshness check reads the same session key the plug sets, so a
  visitor who solved the challenge on a sibling page in the same
  browser continues without re-solving.

  Wire this hook FIRST in the on_mount list of the `:project`,
  `:public_account`, and `:preview_detail` live_sessions. It halts the
  mount and calls `push_navigate/2` when the visitor is anonymous and
  the session has no fresh verification, so no downstream hook does
  expensive work.
  """
  alias Phoenix.LiveView
  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias TuistWeb.Plugs.PublicPageChallengePlug

  def on_mount(:default, _params, session, socket) do
    cond do
      not FeatureFlags.public_page_challenge_enabled?() ->
        {:cont, socket}

      signed_in?(session) ->
        {:cont, socket}

      PublicPageChallengePlug.verified_within_freshness?(session) ->
        {:cont, socket}

      true ->
        {:halt, LiveView.redirect(socket, to: PublicPageChallengePlug.challenge_path())}
    end
  end

  defp signed_in?(session) do
    case session["user_token"] do
      token when is_binary(token) and token != "" ->
        # `get_user_by_session_token` returns nil for a forged or
        # expired token, so we cannot short-circuit on token presence
        # alone. Cheap Redis-backed lookup on the hot path.
        not is_nil(Accounts.get_user_by_session_token(token))

      _ ->
        false
    end
  end
end
