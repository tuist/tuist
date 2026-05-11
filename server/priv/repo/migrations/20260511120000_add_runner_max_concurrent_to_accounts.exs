defmodule Tuist.Repo.Migrations.AddRunnerMaxConcurrentToAccounts do
  use Ecto.Migration

  # The customer's runner-access tier in one column:
  #
  #   runner_max_concurrent = 0  →  runners are disabled for this account
  #   runner_max_concurrent = N  →  at most N concurrent runners
  #
  # The dispatch endpoint counts active Pods labeled
  # `tuist.dev/runner-pool-owner=<account.name>` and rejects the
  # claim when count >= cap. Per-customer JIT mint flows through
  # the existing `vcs.github_app_installations` row (org login =
  # `accounts.name` by convention); we don't keep a per-account
  # GitHub runner-group id here — the JIT mint targets GitHub's
  # default group (id 1). Tightening that into a per-account
  # runner_group_id is a follow-up once multi-tenant onboarding
  # demands repo-level scoping on GitHub's side.
  def change do
    alter table(:accounts) do
      add :runner_max_concurrent, :integer, null: false, default: 0
    end
  end
end
