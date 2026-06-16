defmodule Tuist.Shards do
  @moduledoc """
  Context module for test sharding.

  Handles creating shard plans, computing shard assignments using
  historical timing data, and managing the upload/download of test bundles.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Projects.Project
  alias Tuist.Shards.BinPacker
  alias Tuist.Shards.ShardPlan
  alias Tuist.Shards.ShardPlanModule
  alias Tuist.Shards.ShardPlanTestSuite
  alias Tuist.Storage
  alias Tuist.Tests.TestModuleRun
  alias Tuist.Tests.TestSuiteRun

  @default_module_duration_ms 30_000
  @default_suite_duration_ms 5_000
  @timing_lookback_days 30
  @timing_quantile 0.90

  def create_shard_plan(%Project{} = project, params) do
    granularity = Map.get(params, :granularity, "module")
    reference = Map.fetch!(params, :reference)

    units = extract_units(params, granularity)
    timing_data = fetch_timing_data(project, granularity)
    units_with_durations = assign_durations(units, timing_data, granularity)

    shard_count =
      BinPacker.determine_shard_count(
        units_with_durations,
        min: Map.get(params, :shard_min, 1),
        max: Map.get(params, :shard_max, 10),
        total: Map.get(params, :shard_total),
        max_duration: Map.get(params, :shard_max_duration)
      )

    shards = BinPacker.pack(units_with_durations, shard_count)
    now = NaiveDateTime.utc_now()

    shard_assignments =
      Enum.map(shards, fn {index, shard_units, total} ->
        %{
          "index" => index,
          "test_targets" => Enum.map(shard_units, fn {name, _} -> name end),
          "estimated_duration_ms" => total
        }
      end)

    attrs = %{
      id: Ecto.UUID.generate(),
      reference: reference,
      project_id: project.id,
      shard_count: shard_count,
      granularity: granularity,
      build_run_id: Map.get(params, :build_run_id),
      gradle_build_id: Map.get(params, :gradle_build_id),
      inserted_at: now
    }

    {:ok, plan} = %ShardPlan{} |> ShardPlan.create_changeset(attrs) |> IngestRepo.insert()

    insert_shard_targets(plan, project.id, shards, granularity, now)

    %{
      plan: plan,
      shard_count: shard_count,
      shard_assignments: shard_assignments
    }
  end

  def get_shard_plan(id) do
    case ClickHouseRepo.one(from(s in ShardPlan, where: s.id == ^id, limit: 1)) do
      nil -> {:error, :not_found}
      plan -> {:ok, plan}
    end
  end

  def start_upload(%Project{} = project, %Account{} = account, reference, artifact \\ nil) do
    case get_plan(project.id, reference) do
      nil ->
        {:error, :not_found}

      plan ->
        upload_id = Storage.multipart_start(artifact_object_key(account, project, plan.id, artifact), account)
        {:ok, upload_id}
    end
  end

  def get_shard(%Project{} = project, %Account{} = account, reference, shard_index) do
    case get_plan(project.id, reference) do
      nil ->
        {:error, :not_found}

      plan ->
        case fetch_shard_data(plan, shard_index) do
          nil ->
            {:error, :invalid_shard_index}

          %{modules: modules, suites: suites} ->
            {download_url, download_urls} = shard_download_urls(account, project, plan.id, modules)

            {:ok,
             %{
               shard_plan_id: plan.id,
               modules: modules,
               suites: suites,
               download_url: download_url,
               download_urls: download_urls
             }}
        end
    end
  end

  def complete_upload(%Project{} = project, %Account{} = account, reference, upload_id, parts, artifact \\ nil) do
    case get_plan(project.id, reference) do
      nil ->
        {:error, :not_found}

      plan ->
        Storage.multipart_complete_upload(
          artifact_object_key(account, project, plan.id, artifact),
          upload_id,
          parts,
          account
        )

        :ok
    end
  end

  def generate_upload_url(%Project{} = project, %Account{} = account, reference, upload_id, part_number, artifact \\ nil) do
    case get_plan(project.id, reference) do
      nil ->
        {:error, :not_found}

      plan ->
        url =
          Storage.multipart_generate_url(
            artifact_object_key(account, project, plan.id, artifact),
            upload_id,
            part_number,
            account
          )

        {:ok, url}
    end
  end

  # Each shard downloads only the products it needs: a single `shared` artifact (frameworks,
  # dylibs, the xctestrun, etc.) plus one per-module artifact for each module assigned to the
  # shard. Falls back to the legacy single per-plan bundle when split artifacts weren't uploaded.
  defp shard_download_urls(account, project, plan_id, modules) do
    shared_key = artifact_object_key(account, project, plan_id, "shared")

    if Storage.object_exists?(shared_key, account) do
      shared_url = Storage.generate_download_url(shared_key, account)

      module_urls =
        Enum.map(modules, fn module ->
          Storage.generate_download_url(artifact_object_key(account, project, plan_id, "module:" <> module), account)
        end)

      {nil, [shared_url | module_urls]}
    else
      bundle_url = Storage.generate_download_url(bundle_object_key(account, project, plan_id), account)
      {bundle_url, [bundle_url]}
    end
  end

  def bundle_object_key(account, project, plan_id) do
    "#{account.id}/#{project.id}/shards/#{plan_id}/bundle.zip"
  end

  def artifact_object_key(account, project, plan_id, artifact) do
    base = "#{account.id}/#{project.id}/shards/#{plan_id}"

    case artifact do
      nil -> "#{base}/bundle.zip"
      "shared" -> "#{base}/shared.aar"
      "module:" <> module_name -> "#{base}/modules/#{module_name}.aar"
      _ -> "#{base}/bundle.zip"
    end
  end

  defp insert_shard_targets(plan, project_id, shards, "module", now) do
    rows =
      Enum.flat_map(shards, fn {index, shard_units, _total} ->
        Enum.map(shard_units, fn {name, duration} ->
          %{
            shard_plan_id: plan.id,
            project_id: project_id,
            shard_index: index,
            module_name: name,
            estimated_duration_ms: duration,
            inserted_at: now
          }
        end)
      end)

    if rows != [], do: IngestRepo.insert_all(ShardPlanModule, rows)
  end

  defp insert_shard_targets(plan, project_id, shards, "suite", now) do
    rows =
      Enum.flat_map(shards, fn {index, shard_units, _total} ->
        Enum.map(shard_units, fn {name, duration} ->
          {module_name, test_suite_name} =
            case String.split(name, "/", parts: 2) do
              [mod, suite] -> {mod, suite}
              [mod] -> {mod, mod}
            end

          %{
            shard_plan_id: plan.id,
            project_id: project_id,
            shard_index: index,
            module_name: module_name,
            test_suite_name: test_suite_name,
            estimated_duration_ms: duration,
            inserted_at: now
          }
        end)
      end)

    if rows != [], do: IngestRepo.insert_all(ShardPlanTestSuite, rows)
  end

  defp fetch_shard_data(%ShardPlan{granularity: "module"} = plan, shard_index) do
    plan = ClickHouseRepo.preload(plan, :modules)

    modules =
      plan.modules
      |> Enum.filter(&(&1.shard_index == shard_index))
      |> Enum.map(& &1.module_name)

    if modules == [], do: nil, else: %{modules: modules, suites: %{}}
  end

  defp fetch_shard_data(%ShardPlan{granularity: "suite"} = plan, shard_index) do
    plan = ClickHouseRepo.preload(plan, :test_suites)

    results =
      plan.test_suites
      |> Enum.filter(&(&1.shard_index == shard_index))
      |> Enum.map(&{&1.module_name, &1.test_suite_name})

    if results == [] do
      nil
    else
      suites = Enum.group_by(results, fn {mod, _} -> mod end, fn {_, suite} -> suite end)
      modules = Map.keys(suites)
      %{modules: modules, suites: suites}
    end
  end

  defp get_plan(project_id, reference) do
    ClickHouseRepo.one(
      from(s in ShardPlan,
        where: s.project_id == ^project_id,
        where: s.reference == ^reference,
        order_by: [desc: s.inserted_at],
        limit: 1
      )
    )
  end

  defp extract_units(params, "module"), do: Map.get(params, :modules, [])
  defp extract_units(params, "suite"), do: Map.get(params, :test_suites, [])

  defp fetch_timing_data(project, "module") do
    cutoff = DateTime.add(DateTime.utc_now(), -@timing_lookback_days, :day)

    from(mr in TestModuleRun,
      where: mr.project_id == ^project.id,
      where: mr.is_ci == true,
      where: mr.ran_at >= ^cutoff,
      group_by: mr.name,
      select: %{name: mr.name, duration: fragment("quantile(?)(?)", ^@timing_quantile, mr.duration)}
    )
    |> ClickHouseRepo.all()
    |> Map.new(fn %{name: name, duration: duration} -> {name, round(duration)} end)
  end

  defp fetch_timing_data(project, "suite") do
    cutoff = DateTime.add(DateTime.utc_now(), -@timing_lookback_days, :day)

    from(sr in TestSuiteRun,
      where: sr.project_id == ^project.id,
      where: sr.is_ci == true,
      where: sr.ran_at >= ^cutoff,
      group_by: sr.name,
      select: %{name: sr.name, duration: fragment("quantile(?)(?)", ^@timing_quantile, sr.duration)}
    )
    |> ClickHouseRepo.all()
    |> Map.new(fn %{name: name, duration: duration} -> {name, round(duration)} end)
  end

  defp assign_durations(unit_names, timing_data, granularity) do
    known_durations = Map.values(timing_data)

    default_duration =
      if Enum.empty?(known_durations) do
        case granularity do
          "module" -> @default_module_duration_ms
          "suite" -> @default_suite_duration_ms
        end
      else
        known_durations |> Enum.sort() |> median()
      end

    Enum.map(unit_names, fn name ->
      duration = Map.get(timing_data, name, default_duration)
      {name, duration}
    end)
  end

  defp median(sorted_list) do
    len = length(sorted_list)
    mid = div(len, 2)

    if rem(len, 2) == 0 do
      div(Enum.at(sorted_list, mid - 1) + Enum.at(sorted_list, mid), 2)
    else
      Enum.at(sorted_list, mid)
    end
  end
end
