defmodule Tuist.ProcessorRoleTablesTest do
  @moduledoc """
  Forces a decision about the `tuist_processor` role for every Postgres table.

  The build, xcresult and Bazel processors connect as that role, and
  `Tuist.Release.processor_role_grant_statements/3` grants it an explicit
  allowlist. A table the processors touch but the allowlist misses only fails
  in production, with `42501 insufficient_privilege` mid-ingestion. Every table
  must therefore either be granted there or be listed here as one the
  processors never touch.
  """
  use TuistTestSupport.Cases.DataCase, async: true

  alias Ecto.Adapters.SQL
  alias Tuist.Release

  # Tables the build, xcresult and Bazel processors never read or write.
  @processor_untouched_tables ~w(
    account_cache_endpoints
    account_handle_reservations
    account_token_projects
    account_tokens
    agent_auth_credentials
    agent_auth_jtis
    agent_registration_events
    agent_registrations
    air_usage_notifications
    alert_rules
    alerts
    app_builds
    artifact_retention_cursors
    authorization_requests
    automation_alert_baseline_attempts
    automation_alert_baseline_results
    automation_alert_revisions
    bundle_size_approvals
    bundle_size_approvers
    bundle_thresholds
    cache_action_items
    cache_endpoints
    cache_events
    clickhouse_backfill_chunks
    command_events
    coverage_commit_completions
    device_codes
    git_commit_listings
    git_commit_parents
    git_commits
    git_refs
    git_repositories
    github_app_installations
    guardian_tokens
    invitations
    kura_account_region_lifecycles
    kura_account_region_policies
    kura_claim_proposals
    kura_deployments
    kura_egress_limits
    kura_origin_rollups
    kura_placement_proposals
    kura_placer_claims
    kura_placer_regions
    kura_registered_endpoints
    kura_rollout_events
    kura_rollout_servers
    kura_rollout_wave_assignments
    kura_rollouts
    kura_self_hosted_clients
    kura_servers
    kura_storage_rollups
    oauth2_identities
    oauth_clients
    oauth_clients_scopes
    oauth_scopes
    oauth_tokens
    once_actions
    once_cache_events
    once_runs
    once_system_samples
    once_test_case_runs
    once_test_suite_runs
    organizations
    package_download_events
    package_manifests
    package_releases
    packages
    previews
    project_tokens
    roles
    runner_buildkite_installations
    runner_buildkite_jobs
    runner_cache_volume_measurements
    runner_cache_volume_uses
    runner_cache_volumes
    runner_claims
    runner_concurrency_limits
    runner_gitlab_connections
    runner_gitlab_jobs
    runner_interactive_session_connections
    runner_interactive_sessions
    runner_job_completions
    runner_profiles
    runner_sessions
    runner_volume_affinities
    runner_volume_heads
    runner_volume_master_orphans
    runner_workflow_job_transition_events
    runner_workflow_jobs
    s3_buckets
    schema_migrations
    slack_installations
    ssi_credentials
    subscriptions
    token_usages
    users
    users_roles
    users_tokens
    vcs_connections
  )

  test "every table is either granted to the processor role or declared untouched by it" do
    tables = schema_tables()
    granted = granted_tables()
    untouched = MapSet.new(@processor_untouched_tables)

    unclassified = tables |> MapSet.difference(granted) |> MapSet.difference(untouched)

    assert MapSet.size(unclassified) == 0, """
    These tables are neither granted to the processor role nor declared untouched by it:

      #{unclassified |> Enum.sort() |> Enum.join(", ")}

    Decide whether the build, xcresult or Bazel processors (ProcessBuildWorker,
    ProcessXcresultWorker, the Bazel workers and everything they call,
    including event publishing such as Tuist.MCP.Events.Publisher) read or
    write each table:

      * If they do, grant the narrowest privileges they need in
        Tuist.Release.processor_role_grant_statements/3, mirror the grant in
        infra/cnpg/tuist-processor-grants.sql, and cover that code path in
        test/tuist/processor_role_privileges_test.exs.
      * If they don't, add the table to @processor_untouched_tables in
        #{Path.relative_to_cwd(__ENV__.file)}.
    """
  end

  test "no table is both granted to the processor role and declared untouched by it" do
    overlap = MapSet.intersection(granted_tables(), MapSet.new(@processor_untouched_tables))

    assert MapSet.size(overlap) == 0,
           "Remove #{overlap |> Enum.sort() |> Enum.join(", ")} from @processor_untouched_tables; the processor role is granted access to them."
  end

  test "every table declared untouched by the processor role still exists" do
    stale = @processor_untouched_tables |> MapSet.new() |> MapSet.difference(schema_tables())

    assert MapSet.size(stale) == 0,
           "Remove #{stale |> Enum.sort() |> Enum.join(", ")} from @processor_untouched_tables; the tables no longer exist."
  end

  defp schema_tables do
    %{rows: rows} =
      SQL.query!(Repo, "SELECT tablename FROM pg_tables WHERE schemaname = 'public'", [])

    MapSet.new(rows, fn [table] -> table end)
  end

  defp granted_tables do
    ~s("tuist_processor")
    |> Release.processor_role_grant_statements(~s("tuist"), ~s("public"))
    |> Enum.filter(&(&1 =~ ~r/^GRANT .* ON TABLE /))
    |> Enum.flat_map(&Regex.scan(~r/"public"\.(\w+)/, &1, capture: :all_but_first))
    |> MapSet.new(fn [table] -> table end)
  end
end
