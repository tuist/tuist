defmodule Tuist.FeatureFlags do
  @moduledoc false

  alias Tuist.Environment

  @doc """
  Whether the Runners dashboard (and its sub-pages) should be visible
  for the given account. Canary and production require an explicit
  `:runners` FunWithFlags toggle for the actor. Development, test, and
  staging default to enabled.

  This is also the source of truth for co-located private Kura cache
  infrastructure, so enabling runners provides the cache without a second
  operator-managed switch.
  """
  def runners_enabled?(account) do
    not runner_flag_required?() or FunWithFlags.enabled?(:runners, for: account)
  end

  @doc false
  def runners_enabled?(account, %FunWithFlags.Flag{} = flag) do
    not runner_flag_required?() or FunWithFlags.Flag.enabled?(flag, for: account)
  end

  defp runner_flag_required?, do: Environment.env() in [:can, :prod]

  @doc """
  Whether Kura runtime-image rollouts run through the rollout
  orchestration (`Tuist.Kura.Rollouts`): durable rollout records,
  account-grouped waves with the health gate in production, expedited
  fan-out in the other environments, and the operator verbs.

  On by default in every environment — the machinery soaked on staging
  (spec #79's drills) before the default flipped. The flag is a
  kill-switch, not an opt-in: enabling `kura_rollout_orchestration_kill_switch`
  (via /ops/flags, no deploy) falls back to the interim-paced scheduler
  (`Tuist.Kura.schedule_runtime_image_deployments/0`), which stays the
  no-deploy rollback path.
  """
  def kura_rollout_orchestration_enabled? do
    not FunWithFlags.enabled?(:kura_rollout_orchestration_kill_switch)
  end

  @doc """
  Whether the Cloudflare Turnstile signup gate is active. The env-var
  toggle (`TUIST_TURNSTILE_ENABLED`) still decides which environments
  render the widget at all; the flag on top is a kill switch, not an
  opt-in: enabling `turnstile_kill_switch` (via /ops/flags, no deploy,
  no rolling restart) turns the gate off immediately across every
  replica, everywhere, without touching Helm or the running deployment.
  This is the ops surface the 2026-09-03 outage did not have.
  """
  def turnstile_enabled? do
    Environment.turnstile_required?() and not FunWithFlags.enabled?(:turnstile_kill_switch)
  end

  defimpl FunWithFlags.Actor, for: Tuist.Accounts.User do
    def id(%{id: id}) do
      "user:#{id}"
    end
  end

  defimpl FunWithFlags.Actor, for: Tuist.Accounts.Account do
    def id(%{id: id}) do
      "account:#{id}"
    end
  end

  defimpl FunWithFlags.Actor, for: Tuist.Projects.Project do
    def id(%{id: id}) do
      "project:#{id}"
    end
  end
end
