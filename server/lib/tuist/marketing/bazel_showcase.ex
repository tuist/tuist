defmodule Tuist.Marketing.BazelShowcase do
  @moduledoc """
  Bazel analytics for the live dashboard and invocation timeline embedded in
  the Bazel announcement blog post.

  The post is public and its traffic is mostly anonymous, so everything it
  renders, the timeline and its steps included, is cached briefly instead of
  reloading analytics on every visit. Current project visibility and account
  SSO eligibility are checked before each cache read. Only public projects are
  read, and only aggregates leave the dashboard path: no branches, commits,
  targets, or links into the project's dashboard. Production reads
  `tuist/kura`; development reads `tuist/bazel-comparison`, which
  `priv/repo/seeds.exs` fills with Bazel insights.
  """
  use Supervisor

  import Cachex.Spec, only: [hook: 1]

  alias Tuist.Accounts
  alias Tuist.Bazel
  alias Tuist.Bazel.Timeline
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.KeyValueStore.LoadLimiter
  alias Tuist.Projects
  alias Tuist.Projects.Project
  alias Tuist.ReapiCache

  require Logger

  @period_days 30
  @recent_invocations_limit 30
  @timeline_candidates 50
  @cache_ttl to_timeout(minute: 1)
  @values __MODULE__.Values
  @loaders __MODULE__.Loaders
  # Retained timeline spans are larger than overview widgets. The 32-entry
  # fallback targets 64 MiB of serialized values, before overhead/eviction overshoot.
  @max_value_bytes 2 * 1_024 * 1_024
  @cache_opts [cache: @values, persist_across_deployments: true, ttl: @cache_ttl]

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    children = [
      {Cachex, [@values, [hooks: [hook(module: Cachex.Limit.Evented, args: {32, []})]]]},
      {LoadLimiter,
       Keyword.merge([name: @loaders, queue_timeout: to_timeout(second: 30), on_error: &report_error/1], opts)}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def project_handle do
    if Environment.dev?(), do: "tuist/bazel-comparison", else: "tuist/kura"
  end

  def period_days, do: @period_days

  def get do
    full_handle = project_handle()

    with {:ok, project} <- fetch_project(full_handle) do
      cached(project, :dashboard, fn -> {:ok, analytics(project, full_handle)} end)
    end
  end

  def load(full_handle) do
    case fetch_project(full_handle) do
      {:ok, project} -> {:ok, analytics(project, full_handle)}
      error -> error
    end
  end

  @doc """
  The recent invocation with the richest timeline, so the post shows as much
  of a real build as the project has retained, along with the timeline
  bootstrap the embed renders first.
  """
  def timeline_invocation do
    with {:ok, project} <- fetch_project(project_handle()) do
      selected_timeline(project)
    end
  end

  def load_timeline_invocation(full_handle) do
    with {:ok, project} <- fetch_project(full_handle) do
      load_selected_timeline(project)
    end
  end

  defp load_selected_timeline(project) do
    case richest_timeline_invocation(project) do
      %{} = invocation -> {:ok, %{project: project, invocation: invocation, timeline: Timeline.bootstrap(invocation)}}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  The steps the embedded timeline downloads after it renders. Only the current
  showcase invocation is served, so arbitrary ids can't fill the cache or reach
  the database.
  """
  def timeline_steps(invocation_id) do
    # Finish selection before admitting the steps load: never nest limiter slots.
    with {:ok, project} <- fetch_project(project_handle()),
         {:ok, %{invocation: %{invocation_id: selected_id}}} <- selected_timeline(project) do
      if selected_id == invocation_id do
        cached(project, {:steps, invocation_id}, fn -> load_steps(project, invocation_id) end)
      else
        {:error, :not_found}
      end
    end
  end

  def load_timeline_steps(full_handle, invocation_id) do
    with {:ok, project} <- fetch_project(full_handle) do
      load_steps(project, invocation_id)
    end
  end

  defp load_steps(project, invocation_id) do
    case Bazel.get_invocation(project.id, invocation_id, include_cache_summary: false) do
      {:ok, invocation} -> {:ok, invocation |> Timeline.load() |> Map.delete(:machine_metrics)}
      _ -> {:error, :not_found}
    end
  end

  defp selected_timeline(project) do
    loader = fn ->
      with {:ok, data} <- load_selected_timeline(project), do: {:ok, Map.delete(data, :project)}
    end

    with {:ok, data} <- cached(project, :timeline, loader) do
      {:ok, Map.put(data, :project, project)}
    end
  end

  defp cached(project, operation, loader) do
    identity = {:v1, project.id, project.account.name, project.name, operation}
    key = "marketing-bazel:" <> Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary(identity)), case: :lower)

    case get_cached(key) do
      data when is_map(data) -> {:ok, data}
      _ -> admit(key, loader)
    end
  end

  defp admit(key, loader) do
    case LoadLimiter.run(@loaders, key, fn -> read_or_load(key, loader) end, :infinity) do
      {:ok, result} -> result
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  defp read_or_load(key, loader) do
    # Recheck shared Redis after waiting; cache loss never bypasses admission.
    case get_cached(key) do
      data when is_map(data) ->
        {:ok, data}

      _ ->
        case loader.() do
          {:ok, data} = result ->
            if :erlang.external_size(data) <= @max_value_bytes do
              store(key, data)
            else
              Logger.warning("Bazel showcase value exceeds #{@max_value_bytes} bytes and will not be cached")
            end

            result

          error ->
            error
        end
    end
  end

  defp get_cached(key) do
    KeyValueStore.get(key, @cache_opts)
  rescue
    exception ->
      Logger.warning("Bazel showcase cache read failed: #{Exception.message(exception)}")
      nil
  catch
    :exit, _reason -> nil
  end

  defp store(key, data) do
    KeyValueStore.put(key, data, @cache_opts)
  rescue
    exception -> Logger.warning("Bazel showcase cache write failed: #{Exception.message(exception)}")
  catch
    :exit, _reason -> :ok
  end

  defp report_error({:exception, exception, stacktrace}), do: Sentry.capture_exception(exception, stacktrace: stacktrace)
  defp report_error(_reason), do: :ok

  # The post renders for anonymous visitors, so a project that stops being
  # public falls back to the empty state instead of publishing its analytics.
  defp fetch_project(full_handle) do
    with [account_handle, project_handle] <- String.split(full_handle, "/", parts: 2),
         %Project{visibility: :public} = project <-
           Projects.get_project_by_account_and_project_handles(account_handle, project_handle),
         true <- anonymously_readable_account?(project.account) do
      {:ok, project}
    else
      _ -> {:error, :not_found}
    end
  end

  defp anonymously_readable_account?(%{visibility: :public}), do: true
  defp anonymously_readable_account?(%{organization_id: nil}), do: true

  defp anonymously_readable_account?(%{organization_id: organization_id}) do
    case Accounts.get_organization_by_id(organization_id, preload: []) do
      {:ok, organization} -> not organization.sso_enforced or is_nil(organization.sso_provider)
      {:error, _reason} -> false
    end
  end

  defp analytics(project, full_handle) do
    opts = period_opts()

    summary = Bazel.summary(project.id, opts)
    cache_summary = ReapiCache.summary(project.id, opts)

    recent_invocations =
      project.id
      |> Bazel.recent_invocations(Keyword.put(opts, :limit, @recent_invocations_limit))
      |> Enum.map(&Map.take(&1, [:command, :status, :duration_ms, :finished_at]))

    %{
      project: full_handle,
      invocations: summary.total,
      success_rate: percentage(summary.successful, summary.total),
      median_duration_ms: summary.median_duration_ms,
      cache_hit_rate: cache_summary.hit_rate,
      recent_invocations: recent_invocations
    }
  end

  # Uses the analytics period, so the timeline can't come up empty while the
  # widgets above it show invocations. Candidates arrive newest first, so the
  # newest of equally rich timelines wins.
  defp richest_timeline_invocation(project) do
    project.id
    |> Bazel.recent_invocations(Keyword.put(period_opts(), :limit, @timeline_candidates))
    |> Enum.reject(&(&1.build_timeline_span_start_ms == []))
    |> Enum.max_by(&length(&1.build_timeline_span_start_ms), fn -> nil end)
  end

  defp period_opts do
    end_datetime = DateTime.utc_now()
    [start_datetime: DateTime.add(end_datetime, -@period_days * 86_400, :second), end_datetime: end_datetime]
  end

  defp percentage(_part, total) when total in [nil, 0], do: nil
  defp percentage(part, total), do: Float.round(part / total * 100, 1)
end
