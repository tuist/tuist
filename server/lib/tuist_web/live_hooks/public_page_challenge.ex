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
        # Fresh at mount time is not fresh forever: patch navigation
        # (`push_patch`) does not remount the LiveView, so the wall
        # clock can drift past the freshness window inside the same
        # LiveSocket. `handle_params` fires on every intra-session
        # navigation, so re-running the freshness check there
        # catches the stale case a scraper would otherwise ride out.
        # The session map is closed over so the hook re-reads the
        # same stored timestamp — LiveView will not hand us a fresh
        # session mid-connection.
        hook = fn _params, uri, s -> check_expiry(session, uri, s) end
        {:cont, LiveView.attach_hook(socket, :public_page_challenge_expiry, :handle_params, hook)}

      true ->
        {:halt, redirect_to_challenge(socket, nil)}
    end
  end

  defp check_expiry(session, uri, socket) do
    if PublicPageChallengePlug.verified_within_freshness?(session) do
      {:cont, socket}
    else
      {:halt, redirect_to_challenge(socket, uri)}
    end
  end

  # Preserves the URI the visitor was trying to reach when the mount
  # (or a navigation) was rejected. The controller reads `return_to`
  # from query string first, falling back to the session key the Plug
  # populated on the dead-render path, so both entry vectors land the
  # visitor back where they were after solving the challenge.
  defp redirect_to_challenge(socket, uri) do
    to =
      case return_to_from(uri) do
        nil -> PublicPageChallengePlug.challenge_path()
        path -> PublicPageChallengePlug.challenge_path() <> "?return_to=" <> URI.encode_www_form(path)
      end

    LiveView.redirect(socket, to: to)
  end

  defp return_to_from(nil), do: nil

  defp return_to_from(uri) when is_binary(uri) do
    parsed = URI.parse(uri)

    case parsed.path do
      nil ->
        nil

      path ->
        case parsed.query do
          nil -> path
          "" -> path
          qs -> path <> "?" <> qs
        end
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
