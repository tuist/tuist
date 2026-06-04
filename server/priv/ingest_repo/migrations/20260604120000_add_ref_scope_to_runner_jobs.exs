defmodule Tuist.IngestRepo.Migrations.AddRefScopeToRunnerJobs do
  use Ecto.Migration

  # Carries the GitHub ref-scope dimensions from webhook enqueue through
  # to JIT-mint, so the dispatch-minted cache token can scope the
  # self-hosted GitHub Actions cache the way GitHub's hosted cache does
  # (own ref, PR base ref, default branch; untrusted forks isolated).
  # Without these, the cache gateway could share entries across branches
  # and fork PRs — a cache-poisoning vector.
  def up do
    execute("""
    ALTER TABLE runner_jobs
      ADD COLUMN IF NOT EXISTS default_branch String DEFAULT ''
    """)

    execute("""
    ALTER TABLE runner_jobs
      ADD COLUMN IF NOT EXISTS base_ref String DEFAULT ''
    """)

    execute("""
    ALTER TABLE runner_jobs
      ADD COLUMN IF NOT EXISTS untrusted_fork UInt8 DEFAULT 0
    """)
  end

  def down do
    execute("ALTER TABLE runner_jobs DROP COLUMN IF EXISTS default_branch")
    execute("ALTER TABLE runner_jobs DROP COLUMN IF EXISTS base_ref")
    execute("ALTER TABLE runner_jobs DROP COLUMN IF EXISTS untrusted_fork")
  end
end
