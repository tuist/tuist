defmodule TuistOpsWeb.PolicyController do
  @moduledoc """
  Per-request impersonation resolver for the kubectl gateway.
  Each env runs a `kube-impersonator` sidecar alongside Pomerium
  in the workload cluster's `pomerium` namespace. After Pomerium
  authenticates the user via Google Workspace OIDC and forwards
  the kubectl request to the sidecar, the sidecar dials this
  controller, takes the `Impersonate-User` / `Impersonate-Group`
  response headers, attaches them plus the pod's ServiceAccount
  bearer to the upstream request, and forwards to the apiserver.
  The apiserver RBAC-binds the impersonated group(s).

  ## Wire shape — plain HTTP

  The sidecar speaks plain HTTP (see `kube-impersonator/main.go`).
  We read auth-relevant inputs from request headers it forwards
  and communicate the decision via response status + response
  headers. No Envoy / ext_authz / gRPC framing.

  Inputs (request headers):

    * `host` — derives env ("kube-staging.tuist.dev" → "staging").
      Host header is the source of truth because Pomerium routes
      by host and the same endpoint serves all envs.
    * `x-pomerium-claim-email` — the authenticated user's email,
      set by Pomerium via `jwt_claims_headers: { X-Pomerium-Claim-
      Email: email }` and passed through by the sidecar.

  Outputs:

    * Allow → HTTP 200 with `Impersonate-User: <email>` plus one
      or more `Impersonate-Group:` headers. Multi-group is
      represented as multiple header entries with the same name
      (canonical Kubernetes convention; comma-joining is NOT
      supported by the apiserver).
    * Deny → HTTP 403 with the reason in the body. The sidecar
      surfaces a 502 to kubectl (fail closed).

  ## Tier resolution

  Resolved by the user's Tailscale role (Owner / Admin / Member,
  looked up via `TuistOps.JIT.TailscaleClient.user_role/1`) plus
  any `:active` Elevation row in `tailscale_jit_elevations` for
  (user, env). See `resolve/2` for the full decision table.

  ## Reachability + trust boundary

  Each env's sidecar dials this controller via the cluster-internal
  `tuist-ops-egress` ExternalName Service, which the tailscale-
  operator turns into a tailnet egress proxy reaching
  `ops.<tailnet>.ts.net`. There is no bearer on this call; the
  auth is "you're on the tailnet and the egress Service is in
  your cluster." Public ingress on `ops.tuist.dev` MUST NOT route
  `/api/v1/*` through to this controller — see the ingress
  template in `infra/helm/tuist-ops/`.
  """

  use TuistOpsWeb, :controller

  import Ecto.Query

  alias TuistOps.JIT.Elevation
  alias TuistOps.JIT.Policy
  alias TuistOps.JIT.TailscaleClient
  alias TuistOps.Repo

  require Logger

  def evaluate(conn, _params) do
    case extract_request(conn) do
      {:ok, subject, env} ->
        respond(conn, resolve(subject, env))

      {:error, reason} ->
        Logger.warning("tuist_ops policy: malformed policy request: #{reason}")
        respond(conn, {:deny, "bad request: #{reason}"})
    end
  end

  # --- request extraction ------------------------------------------------

  defp extract_request(conn) do
    with {:ok, env} <- env_from_host(conn.host),
         {:ok, subject} <- subject_from_conn(conn) do
      {:ok, subject, env}
    end
  end

  # "kube-staging.tuist.dev" → "staging". Host header is the source
  # of truth for env because Pomerium routes by Host and the same
  # endpoint serves all envs.
  defp env_from_host("kube-staging.tuist.dev"), do: {:ok, "staging"}
  defp env_from_host("kube-canary.tuist.dev"), do: {:ok, "canary"}
  defp env_from_host("kube-prod.tuist.dev"), do: {:ok, "production"}
  defp env_from_host("kube-production.tuist.dev"), do: {:ok, "production"}
  defp env_from_host(other), do: {:error, "unrecognized host #{inspect(other)}"}

  defp subject_from_conn(conn) do
    case get_req_header(conn, "x-pomerium-claim-email") do
      [email | _] when is_binary(email) and byte_size(email) > 0 -> {:ok, email}
      _ -> {:error, "no x-pomerium-claim-email header"}
    end
  end

  # --- core resolution ---------------------------------------------------

  defp resolve(subject, env) do
    case TailscaleClient.user_role(subject) do
      {:ok, role} ->
        base_groups = base_impersonate_groups(role)

        cond do
          base_groups == [] ->
            {:deny, "role #{inspect(role)} has no cluster access tier"}

          active_elevation?(subject, env) and elevated_allowed?(role, env) ->
            {:allow, subject, base_groups ++ [env_write_group(env)]}

          true ->
            {:allow, subject, base_groups}
        end

      {:error, :not_found} ->
        {:deny, "subject #{subject} not on tailnet"}

      {:error, reason} ->
        Logger.warning(
          "tuist_ops policy: tailnet lookup failed for #{subject}: #{inspect(reason)}"
        )

        {:deny, "tailnet lookup failed"}
    end
  end

  defp base_impersonate_groups(role) when role in [:owner, :admin], do: ["tuist-admins"]
  defp base_impersonate_groups(:member), do: ["tuist-eng"]
  defp base_impersonate_groups(_), do: []

  defp env_write_group("staging"), do: "tuist-staging-write"
  defp env_write_group("canary"), do: "tuist-canary-write"
  defp env_write_group("production"), do: "tuist-production-write"

  # `expires_at > now` enforced at the DB layer so a stale row with
  # status="active" but past expiry never returns elevated headers
  # (defence-in-depth alongside the RevertWorker which flips status
  # at TTL — DB query is the authoritative gate).
  defp active_elevation?(subject, env) do
    target_group = group_for_env(env)
    now = DateTime.utc_now()

    Repo.exists?(
      from(e in Elevation,
        where:
          e.requester_email == ^subject and
            e.target_group == ^target_group and
            e.status == "active" and
            e.expires_at > ^now
      )
    )
  end

  defp group_for_env("staging"), do: "group:tuist-staging-write"
  defp group_for_env("canary"), do: "group:tuist-canary-write"
  defp group_for_env("production"), do: "group:tuist-production-write"

  defp elevated_allowed?(role, env) do
    case Policy.env_access(role, env) do
      {:ok, _} -> true
      :deny -> false
    end
  end

  # --- response shaping --------------------------------------------------

  defp respond(conn, {:allow, subject, impersonate_groups}) do
    conn
    |> put_resp_header("impersonate-user", subject)
    |> add_impersonate_groups(impersonate_groups)
    |> send_resp(200, "")
  end

  defp respond(conn, {:deny, reason}) do
    Logger.info("tuist_ops policy: deny — #{reason}")

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(403, reason)
  end

  # Multi-value `Impersonate-Group` requires multiple separate
  # header entries — comma-joining isn't accepted by the
  # Kubernetes apiserver. Plug's `put_resp_header/3` REPLACES, so
  # we splice the entries onto `resp_headers` directly. Header
  # names are normalised to lowercase per HTTP/2.
  defp add_impersonate_groups(conn, groups) do
    extras = Enum.map(groups, fn group -> {"impersonate-group", group} end)
    %{conn | resp_headers: extras ++ conn.resp_headers}
  end
end
