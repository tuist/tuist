defmodule TuistWeb.OperatorGrant do
  @moduledoc """
  Server side of operator access to customer projects.

  A Tuist operator who isn't a member of a customer account is
  redirected to the ops.tuist.dev reason form, justifies access, and
  comes back with a signed grant token in the query string. This
  module:

    * `verify/1` — verifies that token OFFLINE with the configured
      Ed25519 public key (no runtime call to ops). EdDSA-strict, with
      `exp`, max-TTL ceiling, and `iss`/`aud` pinning.
    * `accept_operator_grant/2` — a plug in `:browser_app` that takes
      the `?operator_grant=` token on the redirect-back, verifies it,
      pins the resolved `account_id` into the claims, stores them in
      the session, and immediately redirects to strip the token from
      the URL (so it never lands in a rendered page, Referer, or the
      observability logs).
    * `load_operator_grant/2` + `on_mount(:load, …)` — attach the
      session grant for the current `account_handle` onto
      `current_user.operator_grant` (controller and LiveView paths).
    * `redirect_to_ops_if_operator/2` — a plug that bounces a
      non-member operator with no grant to the reason form instead of
      404ing them.

  The grant claims stored on the user are a normalised, atom-keyed map
  the authorization checks rely on:

      %{tier: :read | :admin, account_id: integer, account_handle: string,
        sub: string, reason: string, jti: string, iat: integer, exp: integer}

  Revocation is by short TTL (re-checked on every request) plus signing
  key rotation as the break-glass; there is deliberately no server→ops
  call.
  """

  import Phoenix.Controller, only: [redirect: 2, current_url: 1]
  import Plug.Conn

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Environment
  alias Tuist.Projects.Project

  require Logger

  @issuer "ops.tuist.dev"
  @session_key "operator_grants"
  # Tolerance for clock drift between the ops signer and this server.
  @clock_skew_seconds 60

  # --- verification ------------------------------------------------------

  @doc """
  Verifies a grant token and returns its normalised claims, or
  `{:error, reason}`. Fail-closed: an unconfigured public key, a wrong
  algorithm, a bad signature, a missing/over-long TTL, or a wrong
  `iss`/`aud` all reject.
  """
  def verify(token) when is_binary(token) and byte_size(token) > 0 do
    case public_jwk() do
      {:ok, jwk} ->
        # EdDSA-strict: never honour the token's own `alg`, which is the
        # classic JWT confusion attack (`none`/`HS256` signed with the
        # public key). This grants admin, so the allowlist is exactly
        # `["EdDSA"]`.
        case JOSE.JWT.verify_strict(jwk, ["EdDSA"], token) do
          {true, %JOSE.JWT{fields: fields}, _jws} -> validate_claims(fields)
          _ -> {:error, :invalid_signature}
        end

      :error ->
        {:error, :no_public_key}
    end
  end

  def verify(_), do: {:error, :invalid_token}

  defp public_jwk do
    case Environment.operator_grant_public_key() do
      pem when is_binary(pem) and byte_size(pem) > 0 ->
        # A misconfigured key must fail closed, not crash the request.
        try do
          {:ok, JOSE.JWK.from_pem(pem)}
        rescue
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp validate_claims(fields) do
    with {:ok, tier} <- fetch_tier(fields),
         {:ok, account_handle} <- fetch_string(fields, "account_handle"),
         {:ok, sub} <- fetch_string(fields, "sub"),
         {:ok, iat} <- fetch_int(fields, "iat"),
         {:ok, exp} <- fetch_int(fields, "exp"),
         :ok <- check_not_expired(exp),
         :ok <- check_iat_not_future(iat),
         :ok <- check_ttl_ceiling(iat, exp),
         :ok <- check_issuer(fields),
         :ok <- check_audience(fields) do
      {:ok,
       %{
         tier: tier,
         account_handle: account_handle,
         sub: sub,
         reason: Map.get(fields, "reason"),
         jti: Map.get(fields, "jti"),
         iat: iat,
         exp: exp
       }}
    end
  end

  defp fetch_tier(%{"tier" => "read"}), do: {:ok, :read}
  defp fetch_tier(%{"tier" => "admin"}), do: {:ok, :admin}
  defp fetch_tier(_), do: {:error, :invalid_tier}

  defp fetch_string(fields, key) do
    case Map.get(fields, key) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _ -> {:error, {:missing_claim, key}}
    end
  end

  defp fetch_int(fields, key) do
    case Map.get(fields, key) do
      value when is_integer(value) -> {:ok, value}
      _ -> {:error, {:missing_claim, key}}
    end
  end

  defp check_not_expired(exp) do
    if exp > System.system_time(:second), do: :ok, else: {:error, :expired}
  end

  # A future-dated `iat` would otherwise sail past the TTL ceiling
  # (`exp - iat` stays small while `exp` is pushed far out), yielding a
  # long-lived grant. Pinning `iat` to "now" also bounds the absolute
  # expiry to `now + skew + max_ttl`.
  defp check_iat_not_future(iat) do
    if iat <= System.system_time(:second) + @clock_skew_seconds,
      do: :ok,
      else: {:error, :iat_in_future}
  end

  defp check_ttl_ceiling(iat, exp) do
    if exp - iat <= Environment.operator_grant_max_ttl_seconds(),
      do: :ok,
      else: {:error, :ttl_too_long}
  end

  defp check_issuer(%{"iss" => @issuer}), do: :ok
  defp check_issuer(_), do: {:error, :bad_issuer}

  defp check_audience(%{"aud" => aud}) do
    if aud == Environment.operator_grant_audience(), do: :ok, else: {:error, :bad_audience}
  end

  defp check_audience(_), do: {:error, :bad_audience}

  # --- handoff plug (runs in :browser_app) -------------------------------

  @doc """
  If the request carries `?operator_grant=`, verify it, pin the
  account, store it in the session, and redirect to the same path with
  the token stripped. No-ops otherwise.
  """
  def accept_operator_grant(conn, _opts) do
    conn = fetch_query_params(conn)

    case conn.query_params do
      %{"operator_grant" => token} when is_binary(token) -> do_accept(conn, token)
      _ -> conn
    end
  end

  defp do_accept(conn, token) do
    with {:ok, claims} <- verify(token),
         :ok <- check_subject_is_current_operator(conn, claims),
         %{id: account_id} <- Accounts.get_account_by_handle(claims.account_handle) do
      grants =
        conn
        |> get_session(@session_key)
        |> normalize_grants()
        |> Map.put(claims.account_handle, Map.put(claims, :account_id, account_id))

      conn
      |> put_session(@session_key, grants)
      |> redirect(to: stripped_path(conn))
      |> halt()
    else
      _ ->
        # Invalid/unknown token, or a valid token presented by someone
        # who is not the operator it was minted for: strip it and
        # continue unauthenticated. The grant is never stored.
        conn |> redirect(to: stripped_path(conn)) |> halt()
    end
  end

  # The grant is a bearer token, so it must only be honoured for the
  # confirmed operator named in `sub` — otherwise a leaked redirect-back
  # URL would let any logged-in session attach the grant and bypass SSO.
  defp check_subject_is_current_operator(conn, %{sub: sub}) do
    case conn.assigns[:current_user] do
      %User{email: email} = user ->
        if Accounts.tuist_operator?(user) and emails_match?(email, sub) do
          :ok
        else
          Logger.warning("operator grant rejected: subject does not match the session user")
          {:error, :subject_mismatch}
        end

      _ ->
        {:error, :no_current_user}
    end
  end

  defp emails_match?(a, b) when is_binary(a) and is_binary(b) do
    String.downcase(a) == String.downcase(b)
  end

  defp emails_match?(_, _), do: false

  defp normalize_grants(grants) when is_map(grants), do: grants
  defp normalize_grants(_), do: %{}

  defp stripped_path(conn) do
    query =
      conn.query_params
      |> Map.delete("operator_grant")
      |> URI.encode_query()

    if query == "", do: conn.request_path, else: conn.request_path <> "?" <> query
  end

  # --- grant loading (controller + LiveView) -----------------------------

  @doc """
  Controller plug: attach the session grant for the current
  `account_handle` onto `current_user.operator_grant`.
  """
  def load_operator_grant(conn, _opts) do
    with %User{} = user <- conn.assigns[:current_user],
         account_handle when is_binary(account_handle) <- conn.params["account_handle"],
         %{} = claims <- active_session_grant(get_session(conn, @session_key), account_handle) do
      assign(conn, :current_user, %{user | operator_grant: claims})
    else
      _ -> conn
    end
  end

  @doc """
  LiveView on_mount: same as `load_operator_grant/2` but from the
  serialized `session` (the on_mount process has no conn assigns).
  """
  def on_mount(:load, params, session, socket) do
    current_user = socket.assigns[:current_user]
    account_handle = params["account_handle"]
    claims = active_session_grant(session[@session_key], account_handle)

    socket =
      if match?(%User{}, current_user) and is_binary(account_handle) and is_map(claims) do
        Phoenix.Component.assign(socket, :current_user, %{current_user | operator_grant: claims})
      else
        socket
      end

    {:cont, socket}
  end

  @doc """
  True when the current user holds a valid (loaded, unexpired) operator
  grant for the account on this request. Used by the SSO-enforcement
  bypass — so it carries the same operator-identity binding as the
  authorization checks: the session user must be a confirmed Tuist
  operator and the one the grant was minted for.
  """
  def active_grant?(conn) do
    case conn.assigns[:current_user] do
      %User{operator_grant: %{exp: exp} = grant, email: email} = user when is_integer(exp) ->
        exp > System.system_time(:second) and
          Accounts.tuist_operator?(user) and
          emails_match?(email, Map.get(grant, :sub))

      _ ->
        false
    end
  end

  defp active_session_grant(grants, account_handle) when is_map(grants) and is_binary(account_handle) do
    case Map.get(grants, account_handle) do
      %{exp: exp} = claims when is_integer(exp) ->
        if exp > System.system_time(:second), do: claims

      _ ->
        nil
    end
  end

  defp active_session_grant(_grants, _account_handle), do: nil

  # --- redirect-to-ops gate ----------------------------------------------

  @doc """
  Plug: bounce a non-member operator with no grant to the ops reason
  form instead of 404ing. A non-operator, a member, an operator who
  already holds a grant, and a public project all pass through
  untouched.
  """
  def redirect_to_ops_if_operator(conn, _opts) do
    user = conn.assigns[:current_user]
    account_handle = conn.params["account_handle"]
    project_handle = conn.params["project_handle"]

    if ops_redirect_configured?() and google_authenticated?(conn) and
         redirect_to_ops?(user, account_handle, project_handle) do
      conn
      |> redirect(external: ops_reason_form_url(conn, account_handle))
      |> halt()
    else
      conn
    end
  end

  # The reason-form URL is opt-in per environment: until ops.tuist.dev is
  # fronted by Pomerium and routes `/grants` (with a matching per-env
  # audience and return_to allowlist), leave it unset so operators get
  # the normal 404 instead of being bounced to a dead endpoint. Offline
  # grant verification stays active regardless — only the convenience
  # redirect is gated.
  defp ops_redirect_configured? do
    case Environment.ops_reason_form_url() do
      url when is_binary(url) and byte_size(url) > 0 -> true
      _ -> false
    end
  end

  # The "google sso identity under the @tuist.dev org" signal from the
  # requirement: only auto-route operators who actually authenticated
  # via Google Workspace. Keeps password sessions on the normal path.
  defp google_authenticated?(conn), do: get_session(conn, :auth_method) == :google

  defp redirect_to_ops?(%User{operator_grant: grant} = user, account_handle, project_handle)
       when is_binary(account_handle) do
    with true <- is_nil(grant),
         true <- Accounts.tuist_operator?(user),
         account when not is_nil(account) <- Accounts.get_account_by_handle(account_handle),
         false <- Accounts.owns_account_or_belongs_to_account_organization?(user, account),
         false <- public_project?(account_handle, project_handle) do
      true
    else
      _ -> false
    end
  end

  defp redirect_to_ops?(_user, _account_handle, _project_handle), do: false

  # Account-level routes have no public notion; private access there
  # should still route an operator to ops.
  defp public_project?(_account_handle, nil), do: false

  defp public_project?(account_handle, project_handle) do
    case Tuist.Projects.get_project_by_account_and_project_handles(account_handle, project_handle) do
      %Project{} = project -> Tuist.Authorization.authorize(:dashboard_read, nil, project) == :ok
      _ -> false
    end
  end

  defp ops_reason_form_url(conn, account_handle) do
    query =
      URI.encode_query(%{
        "return_to" => current_url(conn),
        "account" => account_handle,
        "tier" => "read"
      })

    Environment.ops_reason_form_url() <> "?" <> query
  end
end
