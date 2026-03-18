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
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestModuleRun
  alias Tuist.Tests.TestSuiteRun

  @default_module_duration_ms 30_000
  @default_suite_duration_ms 5_000
  @timing_lookback_days 30

  def create_shard_plan(%Project{} = project, %Account{} = account, params) do
    granularity = Map.get(params, :granularity, "module")
    plan_id = Map.fetch!(params, :plan_id)

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

    {modules_count, suites_count} = count_targets(units, granularity)

    attrs = %{
      id: Ecto.UUID.generate(),
      plan_id: plan_id,
      project_id: project.id,
      shard_count: shard_count,
      granularity: granularity,
      modules_count: modules_count,
      suites_count: suites_count,
      inserted_at: now
    }

    case %ShardPlan{} |> ShardPlan.create_changeset(attrs) |> IngestRepo.insert() do
      {:ok, plan} ->
        insert_shard_targets(plan_id, project.id, shards, granularity, now)

        upload_id = Storage.multipart_start(bundle_object_key(account, project, plan_id), account)

        {:ok,
         %{
           plan: plan,
           upload_id: upload_id,
           shard_count: shard_count,
           shard_assignments: shard_assignments
         }}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def get_shard(%Project{} = project, %Account{} = account, plan_id, shard_index) do
    case get_plan(project.id, plan_id) do
      nil ->
        {:error, :not_found}

      plan ->
        case fetch_shard_data(plan, plan_id, project.id, shard_index) do
          nil ->
            {:error, :invalid_shard_index}

          %{modules: modules, suites: suites} ->
            download_url =
              Storage.generate_download_url(bundle_object_key(account, project, plan_id), account)

            {:ok,
             %{
               modules: modules,
               suites: suites,
               download_url: download_url
             }}
        end
    end
  end

  def complete_upload(%Project{} = project, %Account{} = account, plan_id, upload_id, parts) do
    Storage.multipart_complete_upload(bundle_object_key(account, project, plan_id), upload_id, parts, account)
    :ok
  end

  def generate_upload_url(%Project{} = project, %Account{} = account, plan_id, upload_id, part_number) do
    url =
      Storage.multipart_generate_url(
        bundle_object_key(account, project, plan_id),
        upload_id,
        part_number,
        account
      )

    {:ok, url}
  end

  defp bundle_object_key(account, project, plan_id) do
    "#{account.id}/#{project.id}/shards/#{plan_id}/bundle.zip"
  end

  defp count_targets(units, "module"), do: {length(units), 0}

  defp count_targets(units, "suite") do
    modules =
      units
      |> Enum.map(fn name ->
        case String.split(name, "/", parts: 2) do
          [mod, _] -> mod
          [mod] -> mod
        end
      end)
      |> Enum.uniq()

    {length(modules), length(units)}
  end

  defp insert_shard_targets(plan_id, project_id, shards, "module", now) do
    rows =
      Enum.flat_map(shards, fn {index, shard_units, _total} ->
        Enum.map(shard_units, fn {name, duration} ->
          %{
            plan_id: plan_id,
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

  defp insert_shard_targets(plan_id, project_id, shards, "suite", now) do
    rows =
      Enum.flat_map(shards, fn {index, shard_units, _total} ->
        Enum.map(shard_units, fn {name, duration} ->
          {module_name, test_suite_name} =
            case String.split(name, "/", parts: 2) do
              [mod, suite] -> {mod, suite}
              [mod] -> {mod, mod}
            end

          %{
            plan_id: plan_id,
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

  defp fetch_shard_data(%ShardPlan{granularity: "module"}, plan_id, project_id, shard_index) do
    modules =
      ClickHouseRepo.all(
        from(m in ShardPlanModule,
          where: m.plan_id == ^plan_id,
          where: m.project_id == ^project_id,
          where: m.shard_index == ^shard_index,
          select: m.module_name
        )
      )

    if modules == [], do: nil, else: %{modules: modules, suites: %{}}
  end

  defp fetch_shard_data(%ShardPlan{granularity: "suite"}, plan_id, project_id, shard_index) do
    results =
      ClickHouseRepo.all(
        from(s in ShardPlanTestSuite,
          where: s.plan_id == ^plan_id,
          where: s.project_id == ^project_id,
          where: s.shard_index == ^shard_index,
          select: {s.module_name, s.test_suite_name}
        )
      )

    if results == [] do
      nil
    else
      suites = Enum.group_by(results, fn {mod, _} -> mod end, fn {_, suite} -> suite end)
      modules = Map.keys(suites)
      %{modules: modules, suites: suites}
    end
  end

  defp get_plan(project_id, plan_id) do
    ClickHouseRepo.one(
      from(s in ShardPlan,
        where: s.project_id == ^project_id,
        where: s.plan_id == ^plan_id,
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
      join: t in Test,
      on: mr.test_run_id == t.id,
      where: t.project_id == ^project.id,
      where: t.is_ci == true,
      where: t.git_branch == ^project.default_branch,
      where: t.ran_at >= ^cutoff,
      group_by: mr.name,
      select: %{name: mr.name, avg_duration: fragment("avg(?)", mr.duration)}
    )
    |> ClickHouseRepo.all()
    |> Map.new(fn %{name: name, avg_duration: avg} -> {name, round(avg)} end)
  end

  defp fetch_timing_data(project, "suite") do
    cutoff = DateTime.add(DateTime.utc_now(), -@timing_lookback_days, :day)

    from(sr in TestSuiteRun,
      join: t in Test,
      on: sr.test_run_id == t.id,
      where: t.project_id == ^project.id,
      where: t.is_ci == true,
      where: t.git_branch == ^project.default_branch,
      where: t.ran_at >= ^cutoff,
      group_by: sr.name,
      select: %{name: sr.name, avg_duration: fragment("avg(?)", sr.duration)}
    )
    |> ClickHouseRepo.all()
    |> Map.new(fn %{name: name, avg_duration: avg} -> {name, round(avg)} end)
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
