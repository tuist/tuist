defmodule Tuist.FeatureFlags do
  @moduledoc false

  alias Tuist.Environment
  alias Tuist.Observability
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage

  @doc "Default-off account opt-in to Pulse; configured tenant ownership and membership still apply."
  def pulse_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :pulse,
      account,
      flag_enabled?(:pulse, account, flags)
    )
  end

  @doc """
  Whether `user` is blocked from sending telemetry from Tuist's clients
  (`TuistWeb.API.TelemetryController`), set with the `:telemetry_blocked`
  FunWithFlags toggle for that user when their clients abuse the endpoint.
  """
  def telemetry_blocked?(user), do: FunWithFlags.enabled?(:telemetry_blocked, for: user)

  @doc "Default-off account opt-in to Linux Bazel remote execution in every environment."
  def bazel_remote_execution_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :bazel_remote_execution,
      account,
      flag_enabled?(:bazel_remote_execution, account, flags)
    )
  end

  @doc """
  Default-off account opt-in to automatic task sizing of remote actions
  (`Tuist.RemoteExecution.TaskSizes`): VMs burst to 8 vCPUs, and each
  action's measured use picks its memory and CPU guarantee. Measurements are
  recorded for every account either way.
  """
  def remote_execution_task_sizing_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :remote_execution_task_sizing,
      account,
      flag_enabled?(:remote_execution_task_sizing, account, flags)
    )
  end

  @doc "Default-off account enrollment in runner-local shard artifact storage."
  def runner_shard_storage_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :runner_shard_storage,
      account,
      flag_enabled?(:runner_shard_storage, account, flags)
    )
  end

  @doc "Default-off account enrollment in public shard artifact storage."
  def public_shard_storage_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :public_shard_storage,
      account,
      flag_enabled?(:public_shard_storage, account, flags)
    )
  end

  @doc """
  Immutable shard plans (version 1) are disabled for every account, whatever
  the `:immutable_shard_reports` toggle says, so every new plan is a legacy one.

  Version-1 plans drop coverage and per-test evidence: the coverage stores pick
  each shard's current report by receipt order, while version-1 reports are
  ordered by producer attempt, and coverage and test selection read every
  attempt's facts from `test_case_runs`/`test_module_runs`. A sharded run on
  such a plan therefore gets no commit coverage and gives test selection no
  baseline or evidence. No account uses immutable plans, so they stay off
  until coverage and test selection read version-1 reports (rows tagged with
  their fact set, run totals derived rather than rewritten). Existing version-1
  plans keep their contract.

  To re-enable, answer with the account's toggle again, and keep projects
  whose coverage still can't be read from version-1 reports on legacy plans.
  """
  def immutable_shard_reports_enabled?(subject, flags \\ nil)

  def immutable_shard_reports_enabled?(%Project{account: account}, _flags), do: immutable_shard_reports_disabled(account)

  def immutable_shard_reports_enabled?(account, _flags), do: immutable_shard_reports_disabled(account)

  defp immutable_shard_reports_disabled(account),
    do: Observability.feature_flag_evaluated(:immutable_shard_reports, account, false)

  @doc "Default-off account opt-in to managed positive-fence serving authority."
  def kura_positive_fence_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :kura_positive_fence,
      account,
      flag_enabled?(:kura_positive_fence, account, flags)
    )
  end

  @doc """
  Default-off account opt-in to one Kura replica per host in regions that
  otherwise co-locate an account's replicas, so the cache survives a host loss.
  """
  def kura_replica_spread_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :kura_replica_spread,
      account,
      flag_enabled?(:kura_replica_spread, account, flags)
    )
  end

  @doc """
  Default-off account opt-in to placement reading what each region served, not
  only where runs report from. Off, placement decides exactly as it did before.
  """
  def kura_placement_served_signal_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :kura_placement_served_signal,
      account,
      flag_enabled?(:kura_placement_served_signal, account, flags)
    )
  end

  @doc """
  Default-off account opt-in to a Kura memory floor the kura-controller raises,
  up to the plan's `floor_max_mib`, when the instance's reads shed for want of
  admission memory. Requires a kura-controller and CRD that know
  `memoryFloorMaxMib`.
  """
  def kura_learned_memory_floor_enabled?(account) do
    FunWithFlags.enabled?(:kura_learned_memory_floor, for: account)
  end

  @doc """
  Default-off account opt-in to Kura data volumes encrypted at rest
  (`kura-encrypted-nvme`) in regions on the node-local NVMe class.
  """
  def kura_encrypted_volumes_enabled?(account) do
    FunWithFlags.enabled?(:kura_encrypted_volumes, for: account)
  end

  @doc """
  Default-off account opt-in to thin encrypted Kura volumes
  (`kura-thin-encrypted-nvme`). It applies only in regions listed in
  `TUIST_KURA_THIN_REGIONS` (`Tuist.Kura.Regions.thin_volumes?/2`).
  """
  def kura_thin_volumes_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :kura_thin_volumes,
      account,
      flag_enabled?(:kura_thin_volumes, account, flags)
    )
  end

  @doc """
  Whether legacy endpoint discovery may hand out the stable hostname. Canary
  enables this automatically; other environments use the account/global flag.
  DNS publication is independent because new CLIs derive that hostname locally.
  """
  def kura_stable_hostname_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :kura_stable_hostname,
      account,
      Environment.env() == :can or flag_enabled?(:kura_stable_hostname, account, flags)
    )
  end

  @doc """
  Whether the account may use agent sandboxes on any platform: the sandbox
  and agent session API, and the work pollers of its agent environments.
  Canary and production require one of the account's sandbox flags, since
  every sandbox runs on shared bare-metal nodes: `:sandboxes` (every
  platform, the early-access flag), `:linux_sandboxes` or `:macos_sandboxes`.
  Which platforms it may create on is `sandbox_platform_enabled?/2`.
  Development, test, and staging default to enabled.
  """
  def sandboxes_enabled?(account) do
    not sandboxes_flag_required?() or
      Enum.any?([:sandboxes, :linux_sandboxes, :macos_sandboxes], &FunWithFlags.enabled?(&1, for: account))
  end

  @doc """
  Whether the account may create sandboxes on `platform` (`:linux` or
  `:darwin`). Canary and production require `:sandboxes` or the platform's
  own flag, `:linux_sandboxes` or `:macos_sandboxes`, so one platform can
  open to every account (the flag's boolean gate) while the other stays
  per account. Sandboxes the account already has keep running either way.
  """
  def sandbox_platform_enabled?(account, platform) when platform in [:linux, :darwin] do
    not sandboxes_flag_required?() or FunWithFlags.enabled?(:sandboxes, for: account) or
      FunWithFlags.enabled?(sandbox_platform_flag(platform), for: account)
  end

  defp sandbox_platform_flag(:linux), do: :linux_sandboxes
  defp sandbox_platform_flag(:darwin), do: :macos_sandboxes

  defp sandboxes_flag_required?, do: Environment.env() in [:can, :prod]

  @doc """
  Global kill switch for copying long remote action logs to object storage:
  while `:remote_action_log_copies_disabled` is on, records get no uploads and
  the gateway copies nothing.
  """
  def remote_action_log_copies_disabled?, do: FunWithFlags.enabled?(:remote_action_log_copies_disabled)

  @doc """
  Whether a user may use Luft's features: threads, AI subscriptions and
  MCP servers. Canary and production require an explicit `:luft` FunWithFlags
  toggle. Development, test and staging default to enabled. Organization
  routing uses `organization_luft_enabled?/1` instead.
  """
  def luft_enabled?(actor) do
    Environment.env() not in [:can, :prod] or FunWithFlags.enabled?(:luft, for: actor)
  end

  @doc "Organization AI requires the account's `:luft` flag in every environment."
  def organization_luft_enabled?(account), do: FunWithFlags.enabled?(:luft, for: account)

  @doc """
  The names of the flags enabled for `user` that the Tuist apps read
  (`GET /api/me/feature-flags`) to show or hide features. Apps treat a flag
  they don't receive as off. Add a flag here, under the name the apps use,
  only when an app feature depends on it.
  """
  def app_flags(user) do
    for {name, true} <- [{"luft", luft_enabled?(user)}], do: name
  end

  @doc "Enabling the pause flag holds current runner limits, globally or for one account."
  def runner_concurrency_growth_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :runner_concurrency_growth_paused,
      account,
      not flag_enabled?(:runner_concurrency_growth_paused, account, flags)
    )
  end

  @doc """
  Whether the account's Linux jobs get a persistent Docker data root per
  repository (`Tuist.Runners.CacheVolumes.allocate_docker/1`). Production
  requires the `:runner_docker_cache` flag for the account during the rollout.
  Canary enables it for qualification without a separate database toggle;
  pool configuration, profile opt-outs and repository authorization still apply.
  Development, test and staging also default to enabled.
  """
  def runner_docker_cache_enabled?(account) do
    Environment.env() != :prod or FunWithFlags.enabled?(:runner_docker_cache, for: account)
  end

  @doc """
  Whether a new Linux sandbox of the account's Claude Code sessions starts with
  a copy of its repository's CI cache volume
  (`Tuist.Runners.CacheVolumes.sandbox_cache/2`). Production requires the
  `:sandbox_runner_cache` flag for the account during the rollout; nodes attach
  a cache only where sandboxd copies them (`CACHE_IMAGES_GIB`).
  """
  def sandbox_runner_cache_enabled?(account) do
    Environment.env() != :prod or FunWithFlags.enabled?(:sandbox_runner_cache, for: account)
  end

  @doc """
  Whether the account's GitHub Actions jobs on Linux runners use the cache the
  runner hosts serve (`Tuist.Runners.ActionsCache`) instead of GitHub's.
  Production requires the `:runner_actions_cache` flag for the account during
  the rollout; other environments default to enabled.
  """
  def runner_actions_cache_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :runner_actions_cache,
      account,
      Environment.env() != :prod or flag_enabled?(:runner_actions_cache, account, flags)
    )
  end

  @doc """
  Whether a verified GitHub Actions OIDC token binds the account's runner
  session to the job it names (`Tuist.Runners.ExecutionTokens.prove/1`).
  Production requires the `:runner_oidc_execution` flag for the account during
  the rollout; without it the server only logs the job a token names.
  Other environments default to enabled.
  """
  def runner_oidc_execution_enabled?(account) do
    Environment.env() != :prod or FunWithFlags.enabled?(:runner_oidc_execution, for: account)
  end

  @doc """
  Whether the account gets a node in the runner-cache region of each site its
  runners are racked at (`Tuist.Kura.Regions.site/1`). A site's region serves
  only that site's pools, so it holds nodes for the accounts the
  `:runner_site_cache` flag enables, in every environment.
  """
  def runner_site_cache_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :runner_site_cache,
      account,
      flag_enabled?(:runner_site_cache, account, flags)
    )
  end

  @doc """
  Whether the account gets a node in the runner-cache region of each site it
  qualifies for (`runner_site_enabled?/2` or `runner_site_cache_enabled?/2`)
  without the cache traffic from the site `Tuist.Kura.RunnerCache` otherwise
  requires. Capacity admission still applies.
  """
  def runner_site_cache_pinned?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :runner_site_cache_pinned,
      account,
      flag_enabled?(:runner_site_cache_pinned, account, flags)
    )
  end

  @doc """
  Whether the account is kept out of every site's runner-cache region, so its
  node there drains and is torn down. Its jobs still run at the site
  (`Tuist.Runners.Dispatch`) and use its other regions' caches.
  """
  def runner_site_cache_excluded?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :runner_site_cache_excluded,
      account,
      flag_enabled?(:runner_site_cache_excluded, account, flags)
    )
  end

  @doc """
  Whether the account gets a node in the site's runner-cache region, as
  `:runner_site_cache` gives one. Every account's macOS jobs run at a site
  regardless (`Tuist.Runners.Dispatch`); the flag is on for every account in
  staging and canary.
  """
  def runner_site_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :runner_site,
      account,
      Environment.env() in [:stag, :can] or flag_enabled?(:runner_site, account, flags)
    )
  end

  @doc """
  Whether coverage-based test selection (test impact analysis) runs for a
  project: the project needs coverage (`Tuist.Tests.Coverage.supported?/1`)
  and its account the `:test_impact_analysis` flag. Canary and production
  require an explicit toggle while development, test, and staging default to
  enabled.
  """
  def test_impact_analysis_enabled?(account, project, flags \\ nil) do
    Coverage.supported?(project) and test_impact_analysis_account_enabled?(account, flags)
  end

  @doc """
  Hosted snapshot testing (`Tuist.Snapshots`): on outside canary and
  production, and behind the `:snapshots` account flag there while it is in
  early access.
  """
  def snapshots_enabled?(account, flags \\ nil)

  def snapshots_enabled?(nil, _flags), do: Observability.feature_flag_evaluated(:snapshots, :unknown, false)

  def snapshots_enabled?(account, flags) do
    Observability.feature_flag_evaluated(
      :snapshots,
      account,
      Environment.env() not in [:can, :prod] or flag_enabled?(:snapshots, account, flags)
    )
  end

  @doc """
  The account's side of `test_impact_analysis_enabled?/3`, without a project:
  its `:test_impact_analysis` toggle. It's what `Tuist.Ops.FeatureFlags`,
  whose evaluations are per account, reports.
  """
  def test_impact_analysis_account_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :test_impact_analysis,
      account,
      Environment.env() not in [:can, :prod] or flag_enabled?(:test_impact_analysis, account, flags)
    )
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
  def kura_rollout_orchestration_enabled?(flags \\ nil) do
    Observability.feature_flag_evaluated(
      :kura_rollout_orchestration,
      nil,
      not flag_enabled?(:kura_rollout_orchestration_kill_switch, nil, flags)
    )
  end

  @doc """
  Whether the Cloudflare Turnstile signup gate is active. The env-var
  toggle (`TUIST_TURNSTILE_ENABLED`) still decides which environments
  render the widget at all; the flag on top is a kill switch, not an
  opt-in: enabling `turnstile_kill_switch` (via /ops/flags, no deploy,
  no rolling restart) publishes cache invalidation across replicas without
  touching Helm or the running deployment. Invalidation is best effort;
  disconnected replicas can retain cached decisions during storage failures.
  This is the ops surface the 2026-09-03 outage did not have.
  """
  def turnstile_enabled?(flags \\ nil) do
    Observability.feature_flag_evaluated(
      :turnstile,
      nil,
      Environment.turnstile_required?() and not flag_enabled?(:turnstile_kill_switch, nil, flags)
    )
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
  def public_page_challenge_enabled?(flags \\ nil) do
    Observability.feature_flag_evaluated(
      :public_page_challenge,
      nil,
      Environment.public_page_challenge_required?() and
        not flag_enabled?(:public_page_challenge_kill_switch, nil, flags)
    )
  end

  @doc """
  Persistent build inventories are opt-in per project. The kill switch stops
  derivation and hides the new surfaces without changing native ingestion.
  """
  def build_entities_enabled?(project, flags \\ nil)

  def build_entities_enabled?(project_id, flags) when is_integer(project_id),
    do: build_entities_enabled?(%Project{id: project_id}, flags)

  def build_entities_enabled?(%Project{} = project, flags) do
    Observability.feature_flag_evaluated(
      :build_entities,
      project,
      not flag_enabled?(:build_entities_kill_switch, nil, flags) and
        flag_enabled?(:build_entities, project, flags)
    )
  end

  # Inspection can supply a batch of persisted flags without populating or
  # mutating the evaluation cache. Ordinary callers retain the cached path.
  @doc false
  def flag_enabled?(name, actor, flags)

  def flag_enabled?(name, nil, nil), do: FunWithFlags.enabled?(name)
  def flag_enabled?(name, actor, nil), do: FunWithFlags.enabled?(name, for: actor)

  def flag_enabled?(name, actor, %FunWithFlags.Flag{name: name} = flag), do: flag_enabled?(name, actor, %{name => flag})

  def flag_enabled?(name, nil, flags), do: FunWithFlags.Flag.enabled?(Map.fetch!(flags, name))
  def flag_enabled?(name, actor, flags), do: FunWithFlags.Flag.enabled?(Map.fetch!(flags, name), for: actor)

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
