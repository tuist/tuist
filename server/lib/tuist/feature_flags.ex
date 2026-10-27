defmodule Tuist.FeatureFlags do
  @moduledoc false

  alias Tuist.Environment
  alias Tuist.Observability
  alias Tuist.Projects.Project

  @doc "Default-off account opt-in to Linux runner pools isolated on vRack-enrolled hosts."
  def runner_linux_vrack_enabled?(account, flags \\ nil) do
    Observability.feature_flag_evaluated(
      :runner_linux_vrack,
      account,
      flag_enabled?(:runner_linux_vrack, account, flags)
    )
  end

  @doc "Default-off immutable shard creation gate; coverage-enabled accounts remain on legacy plans."
  def immutable_shard_reports_enabled?(account, flags \\ nil) do
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
  repository (`Tuist.Runners.CacheVolumes.allocate_docker/1`). Canary and
  production require the `:runner_docker_cache` flag for the account during the
  rollout; development, test and staging default to enabled.
  """
  def runner_docker_cache_enabled?(account) do
    Environment.env() not in [:can, :prod] or FunWithFlags.enabled?(:runner_docker_cache, for: account)
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
  Whether code coverage (Xcode's and Mix's) is ingested, processed and shown
  for the given account. Canary and production require an explicit `:xcode_coverage`
  FunWithFlags toggle for the account while the feature is in early access, so
  its data model and API can still change. Development, test, and staging
  default to enabled.
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
