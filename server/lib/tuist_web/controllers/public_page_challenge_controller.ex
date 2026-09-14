defmodule TuistWeb.PublicPageChallengeController do
  @moduledoc ~S"""
  Serves the Cloudflare Turnstile interstitial that gates anonymous
  entry into public-project and public-account dashboards. Paired
  with `TuistWeb.Plugs.PublicPageChallengePlug` on the dead-render
  path and `TuistWeb.LiveHooks.PublicPageChallenge` on the connected
  LiveView mount.

  ## Endpoints

    * `GET /turnstile-challenge` — renders the challenge page. When
      the challenge is not required (feature flag off, visitor
      already signed in, or session already carries a fresh
      verification) it redirects to the captured return path — or `/`
      when none was captured.

    * `POST /turnstile-challenge/verify` — accepts the token the
      Turnstile widget produced (`cf-turnstile-response`), verifies
      it against Cloudflare's siteverify with the expected action
      pinned to `public_page_challenge`, and on success stores a
      short-lived verification timestamp in the signed Phoenix
      session so subsequent dashboard requests can proceed. Rate
      limited per client IP; a failed verification re-renders the
      challenge page with an error, does NOT clear the return path.

  Response cache is disabled on both endpoints so a browser's back
  button cannot serve a stale success page after the session is
  cleared. Return paths are validated as local (single leading slash,
  no scheme, no protocol-relative form) before honouring them.
  """
  use TuistWeb, :controller

  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias TuistWeb.Authentication
  alias TuistWeb.Plugs.PublicPageChallengePlug
  alias TuistWeb.RateLimit
  alias TuistWeb.RemoteIp
  alias TuistWeb.Turnstile

  require Logger

  @expected_action "public_page_challenge"
  @verify_path "/turnstile-challenge/verify"
  # Bounds how many verify attempts one IP can burn per minute. Sized
  # so a real user with a fat-fingered Turnstile challenge (three or
  # four retries) never trips it, and so a scraper trying to grind
  # tokens against Cloudflare's siteverify from one IP burns out in
  # seconds. Kept as a controller-local constant rather than adding a
  # runtime env override; nothing about this rate depends on
  # deployment scale.
  @verify_rate_limit 30

  def show(conn, _params) do
    cond do
      not FeatureFlags.public_page_challenge_enabled?() ->
        conn |> no_store() |> redirect(to: safe_return_to(conn))

      Authentication.current_user(conn) ->
        conn |> no_store() |> redirect(to: safe_return_to(conn))

      PublicPageChallengePlug.verified_within_freshness?(conn) ->
        conn |> no_store() |> redirect(to: safe_return_to(conn))

      true ->
        conn
        |> no_store()
        |> render(:show,
          turnstile_required?: Turnstile.required?(),
          turnstile_site_key: Turnstile.site_key(),
          expected_action: @expected_action,
          verify_path: @verify_path,
          return_to: get_session(conn, PublicPageChallengePlug.return_to_key()),
          error: nil
        )
    end
  end

  def verify(conn, params) do
    with :ok <- check_rate_limit(conn),
         :ok <- Turnstile.verify(params["cf-turnstile-response"], expected_action: @expected_action) do
      conn
      |> mark_verified()
      |> no_store()
      |> redirect(to: safe_return_to(conn, params["return_to"]))
    else
      {:error, :rate_limited} ->
        conn
        |> put_status(:too_many_requests)
        |> no_store()
        |> render(:show,
          turnstile_required?: Turnstile.required?(),
          turnstile_site_key: Turnstile.site_key(),
          expected_action: @expected_action,
          verify_path: @verify_path,
          return_to: get_session(conn, PublicPageChallengePlug.return_to_key()),
          error: dgettext("dashboard_auth", "Too many attempts. Please wait a moment and try again.")
        )

      {:error, reason} ->
        Logger.info("public_page_challenge verification rejected", reason: inspect(reason))

        conn
        |> put_status(:bad_request)
        |> no_store()
        |> render(:show,
          turnstile_required?: Turnstile.required?(),
          turnstile_site_key: Turnstile.site_key(),
          expected_action: @expected_action,
          verify_path: @verify_path,
          return_to: get_session(conn, PublicPageChallengePlug.return_to_key()),
          error: dgettext("dashboard_auth", "Verification failed. Please try again.")
        )
    end
  end

  defp check_rate_limit(conn) do
    key = "public-page-challenge:verify:ip:#{RemoteIp.get(conn)}"

    case RateLimit.hit(key, limit: @verify_rate_limit, window: to_timeout(minute: 1)) do
      {:allow, _} -> :ok
      {:deny, _} -> {:error, :rate_limited}
    end
  end

  defp mark_verified(conn) do
    now = System.system_time(:second)

    conn
    |> put_session(PublicPageChallengePlug.session_key(), now)
    |> delete_session(PublicPageChallengePlug.return_to_key())
    |> configure_session(renew: true)
  end

  defp no_store(conn) do
    conn
    |> put_resp_header("cache-control", "no-store, no-cache, must-revalidate, max-age=0")
    |> put_resp_header("pragma", "no-cache")
  end

  # A `return_to` value only survives the round trip when it is a
  # local path: single leading `/`, no scheme, no protocol-relative
  # `//` form. Anything else falls back to `/`.
  defp safe_return_to(conn, override \\ nil) do
    candidate =
      override ||
        get_session(conn, PublicPageChallengePlug.return_to_key()) ||
        "/"

    if local_path?(candidate), do: candidate, else: "/"
  end

  defp local_path?("//" <> _), do: false
  defp local_path?("/" <> _), do: true
  defp local_path?(_), do: false

  @doc "Freshness window used by the plug + on_mount, exposed here for tests."
  def freshness_seconds, do: Environment.public_page_challenge_freshness()
end
