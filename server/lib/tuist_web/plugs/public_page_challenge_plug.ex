defmodule TuistWeb.Plugs.PublicPageChallengePlug do
  @moduledoc ~S"""
  Gates the dead-render entry to a public-project or public-account
  dashboard page behind a Cloudflare Turnstile challenge. The paired
  `TuistWeb.LiveHooks.PublicPageChallenge` on_mount hook covers the
  connected LiveView mount so a client that skips the dead render
  cannot bypass the gate.

  A request passes without a challenge when:

    * The `Tuist.FeatureFlags.public_page_challenge_enabled?` gate is
      off. Both the compile-time `TUIST_PUBLIC_PAGE_CHALLENGE_ENABLED`
      env var and the runtime `:public_page_challenge_kill_switch`
      FunWithFlags kill switch must agree for the gate to be on. This
      mirrors the shape signup uses (see
      `Tuist.FeatureFlags.turnstile_enabled?`) so an incident can flip
      the kill switch without a deploy.

    * The request is authenticated. The session cookie carrying a
      valid user token means the visitor is already signed in and the
      dashboard is already gated by its own authorization checks.

    * The session already carries a fresh
      `public_page_challenge_verified_at` timestamp inside the
      freshness window (see
      `Tuist.Environment.public_page_challenge_freshness/0`).

  Otherwise the plug captures the request path + query string as
  `public_page_return_to` in the session and redirects to
  `/turnstile-challenge`. The controller there validates the return
  target as a local path before honouring it.

  Wire this plug into the same `:project`, `:public_account`, and
  `:preview_detail` scope pipelines that already run
  `mark_public_project_page` / `mark_public_account_page` /
  `mark_public_preview_page`. It runs BEFORE the LiveView so the
  redirect happens before any dashboard query fires.
  """
  import Phoenix.Controller, only: [redirect: 2]
  import Plug.Conn

  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias TuistWeb.Authentication

  @session_key "public_page_challenge_verified_at"
  @return_to_key "public_page_return_to"
  @challenge_path "/turnstile-challenge"

  @doc "Session key holding the last verification timestamp (unix seconds)."
  def session_key, do: @session_key

  @doc "Session key holding the return path captured before the challenge."
  def return_to_key, do: @return_to_key

  @doc "URL of the challenge page itself. Kept in one place so callers stay honest."
  def challenge_path, do: @challenge_path

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      not FeatureFlags.public_page_challenge_enabled?() ->
        conn

      Authentication.current_user(conn) ->
        conn

      verified_within_freshness?(conn) ->
        conn

      true ->
        conn
        |> put_session(@return_to_key, return_to(conn))
        |> redirect(to: @challenge_path)
        |> halt()
    end
  end

  @doc """
  Returns true when the session carries a `verified_at` timestamp that
  is still within the configured freshness window. Exposed so the
  matching on_mount hook can share the same predicate against the
  session map LiveView hands it.
  """
  def verified_within_freshness?(%Plug.Conn{} = conn) do
    conn |> get_session(@session_key) |> fresh?()
  end

  def verified_within_freshness?(session) when is_map(session) do
    session |> Map.get(@session_key) |> fresh?()
  end

  defp fresh?(nil), do: false

  defp fresh?(ts) when is_integer(ts) do
    System.system_time(:second) - ts <= Environment.public_page_challenge_freshness()
  end

  defp fresh?(_), do: false

  defp return_to(conn) do
    case conn.query_string do
      "" -> conn.request_path
      qs -> conn.request_path <> "?" <> qs
    end
  end
end
