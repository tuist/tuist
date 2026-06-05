defmodule Tuist.TailscaleJIT.Policy do
  @moduledoc """
  Policy for when a requester can approve their own elevation
  request. The default-deny posture (no self-approval ever) is the
  strongest threat-model stance, but is relaxed in two specific
  places where the operational friction outweighs the agent-
  containment benefit:

    * **Founders can self-approve any env.** The threat model
      accepts that a fully-compromised founder workstation can
      elevate without a second human, on the grounds that the same
      workstation can also drive the 1P kubeconfig bridge (which
      has its own biometric friction). Until the Tailscale-only
      lockdown closes the 1P path, requiring a second human for
      founders adds operational friction without buying real
      defense.

    * **Engineers can self-approve staging and canary.** Production
      still requires a second human, even when requested by an
      engineer. Blast radius of staging/canary writes is contained
      and the elevation flow's audit trail remains intact, so the
      friction of a second human approval isn't earning much.

  The `@admin_emails` list duplicates `group:tuist-admins`
  membership in `infra/tailscale/acls.json` and must be kept in
  sync. When the two diverge the bot is strictly more restrictive
  (an actor not listed here is treated as an engineer for self-
  approval purposes, even if Tailscale's ACL has them in
  `tuist-admins`).
  """

  @admin_emails ~w(marek@tuist.dev pedro@tuist.dev)

  # Mirrors `group:tuist-eng` membership in acls.json. Keeping it
  # explicit (rather than treating "not an admin" as engineer) means
  # an identity not in either list always defaults to deny — useful
  # if the Slack workspace ever has guests or contractors who are
  # not on the tailnet.
  @eng_emails ~w(eduardo.ext@tuist.dev)

  @self_approval_envs_for_eng ~w(staging canary)

  @group_to_env %{
    "group:tuist-staging-write" => "staging",
    "group:tuist-canary-write" => "canary",
    "group:tuist-prod-write" => "production"
  }

  @doc """
  Returns true if `actor_email` is allowed to approve their own
  elevation request for `target_group`. Unknown target groups
  default to deny, regardless of who the actor is.
  """
  def self_approval_allowed?(actor_email, target_group) when is_binary(actor_email) and is_binary(target_group) do
    case Map.get(@group_to_env, target_group) do
      nil ->
        false

      env ->
        cond do
          actor_email in @admin_emails -> true
          actor_email in @eng_emails and env in @self_approval_envs_for_eng -> true
          true -> false
        end
    end
  end

  def self_approval_allowed?(_actor_email, _target_group), do: false

  @doc """
  Returns the configured admin email list. Exposed so the rest of
  the bot can render UI hints that match the policy.
  """
  def admin_emails, do: @admin_emails
end
