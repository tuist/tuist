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
  Whether Xcode code coverage is ingested, processed and shown for the given
  account. Canary and production require an explicit `:xcode_coverage`
  FunWithFlags toggle for the account while the feature is in early access, so
  its data model and API can still change. Development, test, and staging
  default to enabled.
  """
  def xcode_coverage_enabled?(nil), do: false

  def xcode_coverage_enabled?(account) do
    Environment.env() not in [:can, :prod] or FunWithFlags.enabled?(:xcode_coverage, for: account)
  end

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

  @doc """
  Whether anonymous entry to a public-project or public-account
  dashboard has to solve a Cloudflare Turnstile challenge before the
  LiveView mounts. Shape mirrors `turnstile_enabled?`: the env-var
  toggle `TUIST_PUBLIC_PAGE_CHALLENGE_ENABLED` decides where the gate
  is armed at all, and `:public_page_challenge_kill_switch` is a
  flag-flippable emergency off with no deploy required. Off by default
  everywhere so a rollout is one env-var change per environment.
  """
  def public_page_challenge_enabled? do
    Environment.public_page_challenge_required?() and
      not FunWithFlags.enabled?(:public_page_challenge_kill_switch)
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
