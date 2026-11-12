defmodule Tuist.FeatureFlags do
  @moduledoc false

  alias Tuist.Environment
  alias Tuist.Observability
  alias Tuist.Projects.Project

  @doc "Default-off account opt-in to Pulse; configured tenant ownership and membership still apply."
  def pulse_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :pulse,
      account,
      flag_enabled?(:pulse, account, flags)
    )
  end

  @doc "Default-off account opt-in to Linux Bazel remote execution in every environment."
  def bazel_remote_execution_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :bazel_remote_execution,
      account,
      flag_enabled?(:bazel_remote_execution, account, flags)
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

  @doc """
  Default-off immutable shard creation gate. Version-1 plans drop coverage, so
  projects with coverage (`coverage_enabled?/3`: Mix and Cargo projects, and every
  project of a coverage-enabled account) remain on legacy plans. Given an
  account, it answers for the account's other projects.
  """
  def immutable_shard_reports_enabled?(subject, flags \\ nil)

  def immutable_shard_reports_enabled?(%Project{account: account} = project, flags) do
    Observability.feature_flag_evaluated(
      :immutable_shard_reports,
      account,
      flag_enabled?(:immutable_shard_reports, account, flags) and not coverage_enabled?(account, project, flags)
    )
  end

  def immutable_shard_reports_enabled?(account, flags) do
    Observability.feature_flag_evaluated(
      :immutable_shard_reports,
      account,
      flag_enabled?(:immutable_shard_reports, account, flags) and not xcode_coverage_enabled?(account, flags)
    )
  end

  @doc "Default-off account opt-in to managed positive-fence serving authority."
  def kura_positive_fence_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :kura_positive_fence,
      account,
      flag_enabled?(:kura_positive_fence, account, flags)
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
  Whether the account may use agent sandboxes: the sandbox and agent
  session API, and the work pollers of its agent environments. Canary and
  production require an explicit `:sandboxes` FunWithFlags toggle for the
  account, since every sandbox runs on shared bare-metal nodes.
  Development, test, and staging default to enabled.
  """
  def sandboxes_enabled?(account) do
    not sandboxes_flag_required?() or FunWithFlags.enabled?(:sandboxes, for: account)
  end

  defp sandboxes_flag_required?, do: Environment.env() in [:can, :prod]

  @doc """
  Whether a user may use personal AI features. Canary and production require
  an explicit `:ai` FunWithFlags toggle. Development, test and staging default
  to enabled. Organization routing uses `organization_ai_enabled?/1` instead.
  """
  def ai_enabled?(actor) do
    Environment.env() not in [:can, :prod] or FunWithFlags.enabled?(:ai, for: actor)
  end

  @doc "Organization AI requires the account's `:ai` flag in every environment."
  def organization_ai_enabled?(account), do: FunWithFlags.enabled?(:ai, for: account)

  @doc """
  The names of the flags enabled for `user` that the Tuist apps read
  (`GET /api/me/feature-flags`) to show or hide features. Apps treat a flag
  they don't receive as off. Add a flag here, under the name the apps use,
  only when an app feature depends on it.
  """
  def app_flags(user) do
    for {name, true} <- [{"ai", ai_enabled?(user)}], do: name
  end

  @doc """
  Whether the Runners dashboard (and its sub-pages) should be visible
  for the given account. Canary and production require an explicit
  `:runners` FunWithFlags toggle for the actor. Development, test, and
  staging default to enabled.

  This is also the source of truth for co-located private Kura cache
  infrastructure, so enabling runners provides the cache without a second
  operator-managed switch.
  """
  def runners_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :runners,
      account,
      not runner_flag_required?() or flag_enabled?(:runners, account, flags)
    )
  end

  defp runner_flag_required?, do: Environment.env() in [:can, :prod]

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
  (`runner_site_enabled?/2`) and use its other regions' caches.
  """
  def runner_site_cache_excluded?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :runner_site_cache_excluded,
      account,
      flag_enabled?(:runner_site_cache_excluded, account, flags)
    )
  end

  @doc """
  Whether the account's macOS profile jobs run at a site: dispatch routes a
  profile to the same Xcode and shape racked at a site
  (`Tuist.Runners.Catalog.site_pool_name/1`) when one is and the site can
  serve it (`Tuist.Runners.Sites`), and to the rented fleet otherwise; a site
  job queued while the site is down moves to the rented fleet
  (`Tuist.Runners.Workers.SiteSpilloverWorker`). The account also gets a
  node in the site's runner-cache region, as `:runner_site_cache` gives one.
  Staging and canary run their macOS jobs at a site, so it is on for every
  account there.
  """
  def runner_site_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :runner_site,
      account,
      Environment.env() in [:stag, :can] or flag_enabled?(:runner_site, account, flags)
    )
  end

  @doc """
  Whether code coverage is ingested, processed and shown for a project of the
  account. Mix and Cargo projects have it in every account. Every other build
  system (Xcode's coverage and test selection) is in early access behind
  `xcode_coverage_enabled?/2`.
  """
  def coverage_enabled?(account, project, flags \\ nil)

  def coverage_enabled?(_account, %Project{build_system: :mix}, _flags), do: true
  def coverage_enabled?(_account, %Project{build_system: :cargo}, _flags), do: true
  def coverage_enabled?(account, _project, flags), do: xcode_coverage_enabled?(account, flags)

  @doc """
  Whether coverage-based test selection (test impact analysis) runs for a
  project: the project needs coverage (`coverage_enabled?/3`) and its account
  the `:test_impact_analysis` flag. Like `:xcode_coverage`, canary and
  production require an explicit toggle while development, test, and staging
  default to enabled.
  """
  def test_impact_analysis_enabled?(account, project, flags \\ nil) do
    coverage_enabled?(account, project, flags) and
      Observability.feature_flag_evaluated(
        :test_impact_analysis,
        account,
        Environment.env() not in [:can, :prod] or flag_enabled?(:test_impact_analysis, account, flags)
      )
  end

  @doc """
  Whether code coverage is ingested, processed and shown for the account's
  projects other than Mix and Cargo ones (see `coverage_enabled?/3`). Canary and
  production require an explicit `:xcode_coverage` FunWithFlags toggle for the
  account while the feature is in early access, so its data model and API can
  still change. Development, test, and staging default to enabled.
  """
  def xcode_coverage_enabled?(account, flags \\ nil)

  def xcode_coverage_enabled?(nil, _flags), do: Observability.feature_flag_evaluated(:xcode_coverage, :unknown, false)

  def xcode_coverage_enabled?(account, flags) do
    Observability.feature_flag_evaluated(
      :xcode_coverage,
      account,
      Environment.env() not in [:can, :prod] or flag_enabled?(:xcode_coverage, account, flags)
    )
  end

  @doc """
  The account's side of `test_impact_analysis_enabled?/3`, without a project:
  its `:test_impact_analysis` toggle and Xcode coverage. It's what
  `Tuist.Ops.FeatureFlags`, whose evaluations are per account, reports.
  """
  def test_impact_analysis_account_enabled?(account, flags \\ nil) do
    xcode_coverage_enabled?(account, flags) and
      (Environment.env() not in [:can, :prod] or flag_enabled?(:test_impact_analysis, account, flags))
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
