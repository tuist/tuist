defmodule TuistOps.JIT.Policy do
  @moduledoc """
  Authorization policy for the JIT elevation flow. Two decisions
  the bot needs to make and one source of truth (the tailnet role,
  fetched via `TuistOps.JIT.TailscaleClient.user_role/1`):

    * `self_approval_allowed?/2` — can the requester approve their
      own elevation? Owner/Admin and Member roles can all
      self-approve any env, production included: a member may
      self-service a production elevation without a second human.

    * `approver_allowed?/2` — can a second human (whoever clicked
      Approve) authorize this elevation? Owner/Admin and Member can
      all approve any env, production included. (Once members can
      self-approve production, gating the second-human path tighter
      buys nothing — a member could always self-approve instead of
      asking another member to click Approve.)

  Source of truth = the Tailscale tailnet role (`Owner`, `Admin`,
  `Member` etc. as shown in the admin console Users page). Nothing
  hardcodes email lists; new humans on the tailnet inherit policy
  by virtue of their assigned role.

  Unknown emails (not on the tailnet) and roles outside
  Owner/Admin/Member default to deny — admin-flavor roles like
  Auditor or Billing admin are not granted any self-approve or
  approver power because they're not engineering identities.

  Staging sits outside the elevation flow entirely — see
  `always_write_env?/1`. Its write tier is part of every
  engineering identity's baseline, so the impersonation endpoint
  hands it out unconditionally and the Slack bot refuses an
  `/elevate staging` rather than opening an approval for access
  the requester already holds.
  """

  alias TuistOps.JIT.TailscaleClient

  # Maps the env shorthand used in the request to the policy
  # decision matrix. `target_group` retains the `group:tuist-*-write`
  # naming from the original ACL-mutation design for back-compat
  # with the existing DB rows; semantically it's just an env tag now.
  @group_to_env %{
    "group:tuist-staging-write" => "staging",
    "group:tuist-canary-write" => "canary",
    "group:tuist-production-write" => "production"
  }

  # Envs that hand their `tuist-<env>-write` tier to every
  # engineering identity unconditionally — no request, no second
  # human, no TTL. Staging serves no customers and holds nothing
  # we can't rebuild, so gating a pod restart there behind an
  # approval costs more than the containment it buys. Canary and
  # production stay elevation-gated: canary is the first stop of
  # the production release cascade and production is production.
  @always_write_envs ["staging"]

  @doc """
  Returns true if `actor_email` is allowed to approve their own
  elevation request for `target_group`. Unknown target groups
  default to deny, regardless of who the actor is.
  """
  def self_approval_allowed?(actor_email, target_group)
      when is_binary(actor_email) and is_binary(target_group) do
    with true <- Map.has_key?(@group_to_env, target_group),
         {:ok, role} <- TailscaleClient.user_role(actor_email) do
      engineering_role?(role)
    else
      _ -> false
    end
  end

  def self_approval_allowed?(_actor_email, _target_group), do: false

  @doc """
  Returns true if `approver_email` is allowed to be the second
  human on the request — i.e. they hold an engineering tailnet
  role (Owner/Admin/Member), which clears any env. Used in the
  "second-human" path (`actor != requester`).
  """
  def approver_allowed?(approver_email, target_group)
      when is_binary(approver_email) and is_binary(target_group) do
    with true <- Map.has_key?(@group_to_env, target_group),
         {:ok, role} <- TailscaleClient.user_role(approver_email) do
      engineering_role?(role)
    else
      _ -> false
    end
  end

  def approver_allowed?(_approver_email, _target_group), do: false

  @doc """
  Returns the env name (`"staging" | "canary" | "production"`) for a
  given target_group, or `nil` for unknown groups. Used by the
  impersonation policy endpoint to derive the env from a request's
  declared target.
  """
  def env_for(target_group), do: Map.get(@group_to_env, target_group)

  @doc """
  Returns true if `env` grants its `tuist-<env>-write` tier to
  every engineering identity with no elevation. Read by
  `TuistOpsWeb.PolicyController` when deciding whether to inject
  the write group, and by the Slack bot to reject an `/elevate`
  for an env that is already writable.
  """
  def always_write_env?(env) when is_binary(env), do: env in @always_write_envs
  def always_write_env?(_env), do: false

  @doc """
  Returns `{:ok, env}` if the role is allowed to operate on the env,
  `:deny` otherwise. Used by the impersonation policy endpoint when
  deciding whether to inject the elevated impersonation header.
  """
  def env_access(role, env) when is_atom(role) and is_binary(env) do
    if engineering_role?(role), do: {:ok, env}, else: :deny
  end

  # Every engineering identity (Owner, Admin, Member) is cleared for
  # every env, production included — members may self-service a prod
  # elevation without a second human. Role still shapes the base
  # impersonation group elsewhere (tuist-eng vs tuist-admins; see
  # TuistOpsWeb.PolicyController). Non-engineering roles (Auditor,
  # Billing admin, unrecognized) are not cleared.
  defp engineering_role?(role), do: role in [:owner, :admin, :member]
end
