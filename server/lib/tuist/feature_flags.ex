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
  Whether the account may run the stress gate for newly added tests
  (`--stress-new-tests` on the CLI, `stressNewTests` on the Gradle plugin).
  Canary and production require an explicit `:stress_new_tests` FunWithFlags
  toggle for the account; development, test, and staging default to enabled.
  An unentitled account gets a verdict with nothing to stress, so the client
  stays silent and the feature stays dark until it is generally available.
  """
  def stress_new_tests_enabled?(account) do
    Environment.env() not in [:can, :prod] or FunWithFlags.enabled?(:stress_new_tests, for: account)
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
