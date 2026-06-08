defmodule TuistOpsWeb.PolicyController do
  @moduledoc """
  Pomerium ext_authz endpoint. Pomerium dials this on every
  kubectl request that reaches a `kube-<env>.tuist.dev` route,
  after it has authenticated the user via Google Workspace OIDC.
  We resolve the impersonation headers (`Impersonate-User`,
  `Impersonate-Group`) the apiserver should see for this user on
  this env, based on:

    * the user's Tailscale role (Owner / Admin / Member, looked up
      via `TuistOps.JIT.TailscaleClient.user_role/1`), which
      decides the *base* tier (`tuist-admins` or `tuist-eng`);
    * whether there is an `:active` Elevation row in the
      `tailscale_jit_elevations` table for (user, env) at the
      moment of the call, which adds the env-specific write group
      on top.

  ## Request shape

  Pomerium speaks the Envoy External Authorization v3 wire format,
  posting a JSON body that wraps the original HTTP request. We
  read three things out of it:

    * `attributes.request.http.host`  — used to derive the env
      ("kube-staging.tuist.dev" → "staging").
    * `attributes.request.http.headers["x-pomerium-claim-email"]` —
      the authenticated user's email, set by Pomerium after the
      OIDC dance.
    * `attributes.source.principal` — Pomerium's identity URI for
      the caller, used as a fallback if the claim header is absent.

  ## Response shape

  ```json
  // Allowed, view tier (default):
  {
    "status":      { "code": 0 },
    "ok_response": {
      "headers": [
        { "header": { "key": "Impersonate-User",  "value": "marek@tuist.dev" } },
        { "header": { "key": "Impersonate-Group", "value": "tuist-admins"    } }
      ]
    }
  }

  // Allowed, elevated tier (active elevation for this env):
  {
    "status":      { "code": 0 },
    "ok_response": {
      "headers": [
        { "header": { "key": "Impersonate-User",  "value": "marek@tuist.dev" } },
        { "header": { "key": "Impersonate-Group", "value": "tuist-admins"    } },
        { "header": { "key": "Impersonate-Group", "value": "tuist-prod-write" },
          "append_action": "APPEND_IF_EXISTS_OR_ADD" }
      ]
    }
  }

  // Denied (off-tailnet, unknown env, etc.):
  {
    "status":          { "code": 7 },
    "denied_response": { "status": { "code": 403 }, "body": "<reason>" }
  }
  ```

  Pomerium injects `ok_response.headers` into the upstream apiserver
  request. The two `Impersonate-Group` entries with `append_action`
  produce two distinct header lines, which Kubernetes interprets as
  membership in BOTH groups (header repetition is how K8s
  represents multi-valued `Impersonate-Group`).

  ## Reachability + trust boundary

  Pomerium dials this endpoint on the tailnet, at
  `http://ops.<tailnet>.ts.net/api/v1/policy`. There is no bearer
  on this call; the auth is "the caller is on the tailnet and
  could reach a tailnet-tagged Service." Public ingress on
  `ops.tuist.dev` MUST NOT route `/api/v1/*` through to this
  controller — see the ingress config in `infra/helm/tuist-ops/`.
  """

  use TuistOpsWeb, :controller

  import Ecto.Query

  alias TuistOps.JIT.Elevation
  alias TuistOps.JIT.Policy
  alias TuistOps.JIT.TailscaleClient
  alias TuistOps.Repo

  require Logger

  # Envoy External Authorization v3 status codes.
  # https://www.envoyproxy.io/docs/envoy/latest/api-v3/service/auth/v3/external_auth.proto
  @ok 0
  @permission_denied 7

  def evaluate(conn, params) do
    case extract_request(params) do
      {:ok, subject, env} ->
        respond(conn, resolve(subject, env))

      {:error, reason} ->
        Logger.warning("tuist_ops policy: malformed ext_authz request: #{reason}")
        respond(conn, {:deny, "bad request: #{reason}"})
    end
  end

  # --- Envoy ext_authz request extraction --------------------------------

  defp extract_request(%{"attributes" => attrs}) do
    request_http = get_in(attrs, ["request", "http"]) || %{}
    host = Map.get(request_http, "host") || ""
    headers = Map.get(request_http, "headers") || %{}

    with {:ok, env} <- env_from_host(host),
         {:ok, subject} <- subject_from_headers(headers, attrs) do
      {:ok, subject, env}
    end
  end

  defp extract_request(_), do: {:error, "missing attributes"}

  # "kube-staging.tuist.dev" → "staging". Host header is the source
  # of truth for env because Pomerium routes by Host and the same
  # endpoint serves all envs.
  defp env_from_host("kube-staging.tuist.dev"), do: {:ok, "staging"}
  defp env_from_host("kube-canary.tuist.dev"), do: {:ok, "canary"}
  defp env_from_host("kube-prod.tuist.dev"), do: {:ok, "production"}
  defp env_from_host("kube-production.tuist.dev"), do: {:ok, "production"}
  defp env_from_host(other), do: {:error, "unrecognized host #{inspect(other)}"}

  defp subject_from_headers(headers, attrs) do
    case Map.get(headers, "x-pomerium-claim-email") || principal_email(attrs) do
      email when is_binary(email) and byte_size(email) > 0 -> {:ok, email}
      _ -> {:error, "no subject in claim headers or principal"}
    end
  end

  defp principal_email(attrs) do
    case get_in(attrs, ["source", "principal"]) do
      "spiffe://" <> rest -> rest |> String.split("/", parts: 2) |> List.last()
      other when is_binary(other) -> other
      _ -> nil
    end
  end

  # --- core resolution ---------------------------------------------------

  defp resolve(subject, env) do
    case TailscaleClient.user_role(subject) do
      {:ok, role} ->
        base_groups = base_impersonate_groups(role)

        cond do
          # Unknown role tier (Auditor, Billing admin, etc.) → no
          # impersonation at all. Pomerium gets a deny and the
          # request never reaches the apiserver.
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
        Logger.warning("tuist_ops policy: tailnet lookup failed for #{subject}: #{inspect(reason)}")
        {:deny, "tailnet lookup failed"}
    end
  end

  # Owner / Admin → `tuist-admins` (bound to view by default;
  # accessBindings in the tailscale-operator chart map it to a
  # ClusterRole on each cluster).
  # Member → `tuist-eng`.
  # Other roles → no base group, default-deny.
  defp base_impersonate_groups(role) when role in [:owner, :admin], do: ["tuist-admins"]
  defp base_impersonate_groups(:member), do: ["tuist-eng"]
  defp base_impersonate_groups(_), do: []

  defp env_write_group("staging"), do: "tuist-staging-write"
  defp env_write_group("canary"), do: "tuist-canary-write"
  defp env_write_group("production"), do: "tuist-prod-write"

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
  defp group_for_env("production"), do: "group:tuist-prod-write"

  # Matches `Policy.approver_allowed?/2` semantics: production
  # elevation requires Owner/Admin even though a Member could have
  # an active elevation row (the role gate fires on approval, but
  # this is a defence-in-depth check at request time in case the
  # row exists and the role has since changed).
  defp elevated_allowed?(role, env) do
    case Policy.env_access(role, env) do
      {:ok, _} -> true
      :deny -> false
    end
  end

  # --- Envoy ext_authz response shaping ----------------------------------

  defp respond(conn, {:allow, subject, impersonate_groups}) do
    headers =
      [envoy_header("Impersonate-User", subject)] ++
        Enum.map(impersonate_groups, fn group ->
          # `append_action` "APPEND_IF_EXISTS_OR_ADD" makes Pomerium
          # emit one Impersonate-Group line per call rather than
          # comma-joining; K8s expects multi-value via repetition.
          envoy_header("Impersonate-Group", group, append: true)
        end)

    json(conn, %{
      status: %{code: @ok},
      ok_response: %{headers: headers}
    })
  end

  defp respond(conn, {:deny, reason}) do
    Logger.info("tuist_ops policy: deny — #{reason}")

    json(conn, %{
      status: %{code: @permission_denied},
      denied_response: %{
        status: %{code: 403},
        body: reason
      }
    })
  end

  defp envoy_header(key, value, opts \\ []) do
    base = %{header: %{key: key, value: value}}

    if Keyword.get(opts, :append, false) do
      Map.put(base, :append_action, "APPEND_IF_EXISTS_OR_ADD")
    else
      base
    end
  end
end
