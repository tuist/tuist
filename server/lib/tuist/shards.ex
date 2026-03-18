defmodule Tuist.Shards do
  @moduledoc """
  Context module for test sharding.

  Handles creating shard plans, computing shard assignments using
  historical timing data, and managing the upload/download of test bundles.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.IngestRepo
  alias Tuist.Projects.Project
  alias Tuist.Shards.BinPacker
  alias Tuist.Shards.PlistFilter
  alias Tuist.Shards.ShardPlan
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

    shard_assignments =
      Enum.map(shards, fn {index, shard_units, total} ->
        %{
          "index" => index,
          "test_targets" => Enum.map(shard_units, fn {name, _} -> name end),
          "estimated_duration_ms" => total
        }
      end)

    bundle_object_key =
      "#{account.id}/#{project.id}/shards/#{plan_id}/bundle.xctestproducts.zip"

    xctestrun_object_key =
      "#{account.id}/#{project.id}/shards/#{plan_id}/original.xctestrun"

    upload_id = Storage.multipart_start(bundle_object_key, account)

    attrs = %{
      id: Ecto.UUID.generate(),
      plan_id: plan_id,
      project_id: project.id,
      shard_count: shard_count,
      granularity: granularity,
      shard_assignments: ShardPlan.encode_shard_assignments(shard_assignments),
      upload_completed: 0,
      bundle_object_key: bundle_object_key,
      xctestrun_object_key: xctestrun_object_key,
      inserted_at: NaiveDateTime.utc_now()
    }

    case %ShardPlan{} |> ShardPlan.create_changeset(attrs) |> IngestRepo.insert() do
      {:ok, plan} ->
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

  def get_shard_assignment(%Project{} = project, %Account{} = account, plan_id, shard_index) do
    case get_plan(project.id, plan_id) do
      nil ->
        {:error, :not_found}

      plan ->
        assignments = ShardPlan.decode_shard_assignments(plan)

        case Enum.find(assignments, fn a -> a["index"] == shard_index end) do
          nil ->
            {:error, :invalid_shard_index}

          assignment ->
            xctestrun_key =
              "#{account.id}/#{project.id}/shards/#{plan_id}/shard-#{shard_index}.xctestrun"

            xctestrun_download_url = Storage.generate_download_url(xctestrun_key, account)
            bundle_download_url = Storage.generate_download_url(plan.bundle_object_key, account)

            {:ok,
             %{
               test_targets: assignment["test_targets"],
               xctestrun_download_url: xctestrun_download_url,
               bundle_download_url: bundle_download_url
             }}
        end
    end
  end

  def complete_upload(%Project{} = project, %Account{} = account, plan_id, upload_id, parts) do
    case get_plan(project.id, plan_id) do
      nil ->
        {:error, :not_found}

      plan ->
        Storage.multipart_complete_upload(plan.bundle_object_key, upload_id, parts, account)

        assignments = ShardPlan.decode_shard_assignments(plan)
        xctestrun_xml = Storage.get_object_as_string(plan.xctestrun_object_key, account)
        granularity = String.to_existing_atom(plan.granularity)

        Enum.each(assignments, fn assignment ->
          index = assignment["index"]
          test_targets = assignment["test_targets"]
          filtered_xml = filter_for_shard(xctestrun_xml, test_targets, granularity)

          shard_key =
            "#{account.id}/#{project.id}/shards/#{plan_id}/shard-#{index}.xctestrun"

          Storage.put_object(shard_key, filtered_xml, account)
        end)

        updated_attrs =
          plan
          |> Map.from_struct()
          |> Map.delete(:__meta__)
          |> Map.put(:upload_completed, 1)
          |> Map.put(:inserted_at, NaiveDateTime.utc_now())

        IngestRepo.insert_all(ShardPlan, [updated_attrs])

        {:ok, plan}
    end
  end

  def generate_upload_url(%Project{} = project, %Account{} = account, plan_id, upload_id, part_number) do
    case get_plan(project.id, plan_id) do
      nil ->
        {:error, :not_found}

      plan ->
        url =
          Storage.multipart_generate_url(
            plan.bundle_object_key,
            upload_id,
            part_number,
            account
          )

        {:ok, url}
    end
  end

  def generate_xctestrun_upload_url(%Project{} = project, %Account{} = account, plan_id) do
    case get_plan(project.id, plan_id) do
      nil ->
        {:error, :not_found}

      plan ->
        url = Storage.generate_upload_url(plan.xctestrun_object_key, account)
        {:ok, url}
    end
  end

  defp get_plan(project_id, plan_id) do
    IngestRepo.one(
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
    |> IngestRepo.all()
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
    |> IngestRepo.all()
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

  defp filter_for_shard(xctestrun_xml, test_targets, :module) do
    PlistFilter.filter_xctestrun(xctestrun_xml, test_targets, :module)
  end

  defp filter_for_shard(xctestrun_xml, test_targets, :suite) do
    targets_map =
      Enum.group_by(
        test_targets,
        fn target ->
          case String.split(target, "/", parts: 2) do
            [module, _suite] -> module
            [name] -> name
          end
        end,
        fn target ->
          case String.split(target, "/", parts: 2) do
            [_module, suite] -> suite
            [name] -> name
          end
        end
      )

    PlistFilter.filter_xctestrun(xctestrun_xml, targets_map, :suite)
  end
end
