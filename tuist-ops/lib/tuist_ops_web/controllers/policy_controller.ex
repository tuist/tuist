defmodule TuistOpsWeb.PolicyController do
  @moduledoc """
  Pomerium ext_authz endpoint. Called by Pomerium on every inbound
  kubectl request to resolve impersonation headers for the
  authenticated user. The response shape matches Pomerium's
  "external policy" contract: a JSON body containing the headers
  Pomerium should inject into the upstream request, plus an
  allow/deny verdict.

  Authentication of the *user* is done by Pomerium itself (Google
  Workspace OIDC). Authentication of *Pomerium-calling-us* is via
  network boundary (Pomerium sits inside the cluster, dials this
  service on the cluster network only). If we ever expose this
  endpoint more broadly, add mTLS or a shared-secret check on the
  pipeline.

  Request body (Pomerium-style):
      {
        "subject": "marek@tuist.dev",
        "env":     "production"           # one of staging|canary|production
      }

  Response body (allow):
      {
        "allow": true,
        "impersonate_user":   "marek@tuist.dev",
        "impersonate_groups": ["tuist-admins"]                # view tier
      }

      {
        "allow": true,
        "impersonate_user":   "marek@tuist.dev",
        "impersonate_groups": ["tuist-admins", "tuist-prod-write"]   # elevated
      }

  Response body (deny):
      { "allow": false, "reason": "<short string>" }
  """

  use TuistOpsWeb, :controller

  import Ecto.Query

  alias TuistOps.JIT.Elevation
  alias TuistOps.JIT.Policy
  alias TuistOps.Repo
  alias TuistOps.JIT.TailscaleClient

  require Logger

  @valid_envs ~w(staging canary production)

  def evaluate(conn, %{"subject" => subject, "env" => env}) when is_binary(subject) and env in @valid_envs do
    case resolve(subject, env) do
      {:allow, user, groups} ->
        json(conn, %{
          allow: true,
          impersonate_user: user,
          impersonate_groups: groups
        })

      {:deny, reason} ->
        Logger.info("tuist_ops policy: deny subject=#{subject} env=#{env} reason=#{reason}")
        json(conn, %{allow: false, reason: reason})
    end
  end

  def evaluate(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{allow: false, reason: "invalid request: expected {subject, env}"})
  end

  # --- core resolution ---------------------------------------------------

  defp resolve(subject, env) do
    case TailscaleClient.user_role(subject) do
      {:ok, role} ->
        base_groups = base_impersonate_groups(role)

        cond do
          # Unknown role tier (Auditor, Billing admin, etc.) → no
          # impersonation at all. Pomerium will receive `allow: true`
          # with empty groups, but RBAC will reject everything since
          # the impersonated identity has no ClusterRole bindings.
          # Default-deny via empty group set rather than a 403 so
          # the same response shape always carries through.
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
end
