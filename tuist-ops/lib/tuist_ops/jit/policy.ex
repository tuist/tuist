defmodule TuistOps.JIT.Policy do
  @moduledoc """
  Authorization policy for the JIT elevation flow. Two decisions
  the bot needs to make and one source of truth (the tailnet role,
  fetched via `TuistOps.JIT.TailscaleClient.user_role/1`):

    * `self_approval_allowed?/2` — can the requester approve their
      own elevation? Owner/Admin roles can self-approve any env;
      Member can self-approve `staging` and `canary` only.

    * `approver_allowed?/2` — can a second human (whoever clicked
      Approve) authorize this elevation? Owner/Admin can approve
      any env; Member can approve `staging` and `canary`. Production
      always requires an Owner/Admin to click Approve, regardless of
      whether the requester is the same person or someone else.

  Source of truth = the Tailscale tailnet role (`Owner`, `Admin`,
  `Member` etc. as shown in the admin console Users page). Nothing
  hardcodes email lists; new humans on the tailnet inherit policy
  by virtue of their assigned role.

  Unknown emails (not on the tailnet) and roles outside
  Owner/Admin/Member default to deny — admin-flavor roles like
  Auditor or Billing admin are not granted any self-approve or
  approver power because they're not engineering identities.
  """

  alias TuistOps.JIT.TailscaleClient

  # Maps the env shorthand used in the request to the policy
  # decision matrix. `target_group` retains the `group:tuist-*-write`
  # naming from the original ACL-mutation design for back-compat
  # with the existing DB rows; semantically it's just an env tag now.
  @group_to_env %{
    "group:tuist-staging-write" => "staging",
    "group:tuist-canary-write" => "canary",
    "group:tuist-prod-write" => "production"
  }

  # Roles that map to the "engineer / member" tier — staging and
  # canary self-approve / approve, but not production.
  @member_envs ~w(staging canary)

  @doc """
  Returns true if `actor_email` is allowed to approve their own
  elevation request for `target_group`. Unknown target groups
  default to deny, regardless of who the actor is.
  """
  def self_approval_allowed?(actor_email, target_group)
      when is_binary(actor_email) and is_binary(target_group) do
    with env when not is_nil(env) <- Map.get(@group_to_env, target_group),
         {:ok, role} <- TailscaleClient.user_role(actor_email) do
      allow_for_env?(role, env)
    else
      _ -> false
    end
  end

  def self_approval_allowed?(_actor_email, _target_group), do: false

  @doc """
  Returns true if `approver_email` is allowed to be the second
  human on the request — i.e. their tailnet role is high enough
  for the env they're approving. Used in the "second-human" path
  (`actor != requester`) to keep an engineer from approving
  another engineer's production write.
  """
  def approver_allowed?(approver_email, target_group)
      when is_binary(approver_email) and is_binary(target_group) do
    with env when not is_nil(env) <- Map.get(@group_to_env, target_group),
         {:ok, role} <- TailscaleClient.user_role(approver_email) do
      allow_for_env?(role, env)
    else
      _ -> false
    end
  end

  def approver_allowed?(_approver_email, _target_group), do: false

  @doc """
  Returns the env name (`"staging" | "canary" | "production"`) for a
  given target_group, or `nil` for unknown groups. Used by the
  Pomerium ext_authz endpoint to derive the env from a request's
  declared target.
  """
  def env_for(target_group), do: Map.get(@group_to_env, target_group)

  @doc """
  Returns `{:ok, env}` if the role is allowed to operate on the env,
  `:deny` otherwise. Used by the Pomerium ext_authz endpoint when
  deciding whether to inject the elevated impersonation header.
  """
  def env_access(role, env) when is_atom(role) and is_binary(env) do
    if allow_for_env?(role, env), do: {:ok, env}, else: :deny
  end

  # Owner/Admin → any env. Member → staging + canary. Everything
  # else (Auditor, Billing admin, etc., and unrecognized roles)
  # falls through to deny.
  defp allow_for_env?(role, _env) when role in [:owner, :admin], do: true
  defp allow_for_env?(:member, env) when env in @member_envs, do: true
  defp allow_for_env?(_role, _env), do: false
end
