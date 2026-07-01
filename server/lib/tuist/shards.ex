defmodule Tuist.Shards do
  @moduledoc """
  Context module for test sharding.

  Handles creating shard plans, computing shard assignments using
  historical timing data, and managing the upload/download of test bundles.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Builds
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

    timing_data = fetch_timing_data(project, granularity)
    units = resolve_units(project, params, granularity, timing_data)
    units_with_durations = assign_durations(units, timing_data, granularity)

    shard_count =
      BinPacker.determine_shard_count(
        units_with_durations,
        min: Map.get(params, :shard_min, 1),
        max: Map.get(params, :shard_max, 10),
        total: Map.get(params, :shard_total),
        max_duration: Map.get(params, :shard_max_duration)
      )

    assignment_shards = BinPacker.pack(units_with_durations, shard_count)

    now = NaiveDateTime.utc_now()

    shard_assignments =
      Enum.map(assignment_shards, fn {index, shard_units, total} ->
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

    insert_shard_targets(plan, project.id, assignment_shards, granularity, now)

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

  def start_upload(%Project{} = project, %Account{} = account, reference) do
    case get_plan(project.id, reference) do
      nil ->
        {:error, :not_found}

      plan ->
        start_upload_for_plan(project, account, plan)
    end
  end

  def start_upload_for_plan(%Project{} = project, %Account{} = account, %ShardPlan{} = plan) do
    start_upload_for_plan_id(project, account, plan.id)
  end

  def start_upload_for_plan_id(%Project{} = project, %Account{} = account, plan_id) do
    upload_id = Storage.multipart_start(bundle_object_key(account, project, plan_id), account)
    {:ok, upload_id}
  end

  def get_shard(%Project{} = project, %Account{} = account, reference, shard_index, opts \\ []) do
    case get_plan(project.id, reference) do
      nil ->
        {:error, :not_found}

      plan ->
        case fetch_shard_data(plan, shard_index, opts) do
          nil ->
            {:error, :invalid_shard_index}

          %{modules: modules, suites: suites, skip: skip} ->
            download_url =
              Storage.generate_download_url(bundle_object_key(account, project, plan.id), account)

            {:ok,
             %{
               shard_plan_id: plan.id,
               modules: modules,
               suites: suites,
               skip: skip,
               download_url: download_url
             }}
        end
    end
  end

  def complete_upload(%Project{} = project, %Account{} = account, reference, upload_id, parts) do
    case get_plan(project.id, reference) do
      nil ->
        {:error, :not_found}

      plan ->
        complete_upload_for_plan(project, account, plan.id, upload_id, parts)
    end
  end

  def complete_upload_for_plan(%Project{} = project, %Account{} = account, plan_id, upload_id, parts) do
    Storage.multipart_complete_upload(bundle_object_key(account, project, plan_id), upload_id, parts, account)
    :ok
  end

  def generate_upload_url(%Project{} = project, %Account{} = account, reference, upload_id, part_number) do
    case get_plan(project.id, reference) do
      nil ->
        {:error, :not_found}

      plan ->
        generate_upload_url_for_plan(project, account, plan.id, upload_id, part_number)
    end
  end

  def generate_upload_url_for_plan(%Project{} = project, %Account{} = account, plan_id, upload_id, part_number) do
    url =
      Storage.multipart_generate_url(
        bundle_object_key(account, project, plan_id),
        upload_id,
        part_number,
        account
      )

    {:ok, url}
  end

  def bundle_object_key(account, project, plan_id) do
    "#{account.id}/#{project.id}/shards/#{plan_id}/bundle.zip"
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

  defp fetch_shard_data(%ShardPlan{granularity: "module"} = plan, shard_index, _opts) do
    plan = ClickHouseRepo.preload(plan, :modules)

    modules =
      plan.modules
      |> Enum.filter(&(&1.shard_index == shard_index))
      |> Enum.map(& &1.module_name)

    if modules == [], do: nil, else: %{modules: modules, suites: %{}, skip: []}
  end

  defp fetch_shard_data(%ShardPlan{granularity: "suite"} = plan, shard_index, opts) do
    plan = ClickHouseRepo.preload(plan, :test_suites)
    suite_catch_all? = Keyword.get(opts, :suite_catch_all?, false)

    results =
      plan.test_suites
      |> Enum.filter(&(&1.shard_index == shard_index))
      |> Enum.map(&{&1.module_name, &1.test_suite_name})

    cond do
      shard_index < 0 or shard_index >= plan.shard_count ->
        nil

      suite_catch_all? and shard_index == plan.shard_count - 1 ->
        skip =
          plan.test_suites
          |> Enum.filter(&(&1.shard_index < shard_index))
          |> Enum.map(&"#{&1.module_name}/#{&1.test_suite_name}")

        %{modules: [], suites: %{}, skip: skip}

      results == [] ->
        if shard_index == plan.shard_count - 1 do
          %{modules: [], suites: %{}, skip: []}
        end

      true ->
        suites = Enum.group_by(results, fn {mod, _} -> mod end, fn {_, suite} -> suite end)
        modules = Map.keys(suites)
        %{modules: modules, suites: suites, skip: []}
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

  defp resolve_units(_project, params, "module", _timing_data), do: Map.get(params, :modules, [])

  defp resolve_units(project, params, "suite", _timing_data) do
    case Map.get(params, :test_suites, []) do
      suites when suites != [] ->
        suites

      _ ->
        latest_branch_suite_units(project, params, Map.get(params, :modules, []))
    end
  end

  defp latest_branch_suite_units(_project, _params, []), do: []

  defp latest_branch_suite_units(project, params, modules) do
    modules = Enum.uniq(modules)
    branches = suite_inventory_branches(project, params)
    suites_by_branch_module = latest_branch_module_suite_units(project, branches, modules)

    modules
    |> Enum.flat_map(fn module ->
      branches
      |> Enum.find_value(fn branch -> Map.get(suites_by_branch_module, {branch, module}) end)
      |> List.wrap()
    end)
    |> Enum.uniq()
  end

  defp suite_inventory_branches(project, params) do
    [
      Map.get(params, :git_branch),
      build_run_git_branch(project, Map.get(params, :build_run_id)),
      project.default_branch
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
  end

  defp build_run_git_branch(_project, nil), do: nil

  defp build_run_git_branch(project, build_run_id) do
    case Builds.get_build(build_run_id, project_id: project.id) do
      {:ok, build} -> build.git_branch
      {:error, :not_found} -> nil
    end
  end

  defp latest_branch_module_suite_units(_project, [], _modules), do: %{}
  defp latest_branch_module_suite_units(_project, _branches, []), do: %{}

  defp latest_branch_module_suite_units(project, branches, modules) do
    cutoff = DateTime.add(DateTime.utc_now(), -@timing_lookback_days, :day)

    latest_module_runs_query =
      from(mr in TestModuleRun,
        where: mr.project_id == ^project.id,
        where: mr.is_ci == true,
        where: mr.git_branch in ^branches,
        where: mr.ran_at >= ^cutoff,
        where: mr.name in ^modules,
        where: mr.test_suite_count > 0,
        group_by: [mr.git_branch, mr.name],
        select: %{
          branch: mr.git_branch,
          module_name: mr.name,
          test_run_id: fragment("argMax(?, ?)", mr.test_run_id, mr.ran_at)
        }
      )

    from(sr in TestSuiteRun,
      join: mr in TestModuleRun,
      on: sr.test_module_run_id == mr.id,
      join: latest in subquery(latest_module_runs_query),
      on:
        latest.test_run_id == sr.test_run_id and latest.module_name == mr.name and
          latest.branch == sr.git_branch,
      where: sr.project_id == ^project.id,
      where: sr.is_ci == true,
      where: sr.git_branch in ^branches,
      where: sr.ran_at >= ^cutoff,
      where: mr.name in ^modules,
      group_by: [latest.branch, latest.module_name, sr.name],
      select: %{
        branch: latest.branch,
        module: latest.module_name,
        name: fragment("concat(?, '/', ?)", latest.module_name, sr.name)
      }
    )
    |> ClickHouseRepo.all()
    |> Enum.group_by(fn row -> {row.branch, row.module} end, & &1.name)
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

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
      join: mr in TestModuleRun,
      on: sr.test_module_run_id == mr.id,
      where: sr.project_id == ^project.id,
      where: sr.is_ci == true,
      where: sr.ran_at >= ^cutoff,
      group_by: fragment("concat(?, '/', ?)", mr.name, sr.name),
      select: %{
        name: fragment("concat(?, '/', ?)", mr.name, sr.name),
        duration: fragment("quantile(?)(?)", ^@timing_quantile, sr.duration)
      }
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
