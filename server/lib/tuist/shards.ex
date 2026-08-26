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
  @suite_inventory_runs 5
  @timing_quantile 0.90
  @min_parallelism_factor 0.5
  @max_parallelism_factor 16.0

  def create_shard_plan(%Project{} = project, params) do
    granularity = Map.get(params, :granularity, "module")
    reference = Map.fetch!(params, :reference)

    units = resolve_units(project, params, granularity)
    timing_data = fetch_timing_data(project, granularity, units)

    units_with_durations =
      units
      |> assign_durations(timing_data, granularity)
      |> scale_by_module_parallelism(project, params, granularity)

    shard_count =
      BinPacker.determine_shard_count(
        units_with_durations,
        min: Map.get(params, :shard_min, 1),
        max: Map.get(params, :shard_max, 10),
        total: Map.get(params, :shard_total),
        max_duration: Map.get(params, :shard_max_duration)
      )

    assignment_shards =
      if granularity == "suite" do
        BinPacker.pack(units_with_durations, shard_count, &suite_module/1)
      else
        BinPacker.pack(units_with_durations, shard_count)
      end

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

    insert_shard_targets(
      plan,
      project.id,
      assignment_shards,
      granularity,
      now,
      module_inventory(params, units, granularity)
    )

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
        start_upload_for_plan(project, account, plan, artifact)
    end
  end

  def start_upload_for_plan(%Project{} = project, %Account{} = account, %ShardPlan{} = plan, artifact \\ nil) do
    start_upload_for_plan_id(project, account, plan.id, artifact)
  end

  def start_upload_for_plan_id(%Project{} = project, %Account{} = account, plan_id, artifact \\ nil) do
    upload_id = Storage.multipart_start(artifact_object_key(account, project, plan_id, artifact), account)
    {:ok, upload_id}
  end

  def get_shard(%Project{} = project, %Account{} = account, reference, shard_index, opts \\ []) do
    case get_plan(project.id, reference) do
      nil ->
        {:error, :not_found}

      plan ->
        get_shard_for_plan(project, account, plan, shard_index, opts)
    end
  end

  def get_shard_for_plan_id(%Project{} = project, %Account{} = account, plan_id, shard_index, opts \\ []) do
    case get_plan_by_id(project.id, plan_id) do
      nil ->
        {:error, :not_found}

      plan ->
        get_shard_for_plan(project, account, plan, shard_index, opts)
    end
  end

  def complete_upload(%Project{} = project, %Account{} = account, reference, upload_id, parts, artifact \\ nil) do
    case get_plan(project.id, reference) do
      nil ->
        {:error, :not_found}

      plan ->
        complete_upload_for_plan(project, account, plan.id, upload_id, parts, artifact)
    end
  end

  def complete_upload_for_plan(%Project{} = project, %Account{} = account, plan_id, upload_id, parts, artifact \\ nil) do
    Storage.multipart_complete_upload(
      artifact_object_key(account, project, plan_id, artifact),
      upload_id,
      parts,
      account
    )

    :ok
  end

  def generate_upload_url(%Project{} = project, %Account{} = account, reference, upload_id, part_number, artifact \\ nil) do
    case get_plan(project.id, reference) do
      nil ->
        {:error, :not_found}

      plan ->
        generate_upload_url_for_plan(project, account, plan.id, upload_id, part_number, artifact)
    end
  end

  def generate_upload_url_for_plan(
        %Project{} = project,
        %Account{} = account,
        plan_id,
        upload_id,
        part_number,
        artifact \\ nil
      ) do
    url =
      Storage.multipart_generate_url(
        artifact_object_key(account, project, plan_id, artifact),
        upload_id,
        part_number,
        account
      )

    {:ok, url}
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

  defp insert_shard_targets(plan, project_id, shards, "module", now, _module_inventory) do
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

  defp insert_shard_targets(plan, project_id, shards, "suite", now, module_inventory) do
    suite_rows =
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

    if suite_rows != [], do: IngestRepo.insert_all(ShardPlanTestSuite, suite_rows)

    # Record the products each shard must download. Regular shards need only their assigned suites'
    # modules; the catch-all shard runs everything not skipped, so it downloads the full built-module
    # inventory (which includes targets that have no suite history and therefore no planned suites).
    insert_suite_download_modules(plan, project_id, shards, module_inventory, now)
  end

  defp insert_suite_download_modules(plan, project_id, shards, module_inventory, now) do
    catch_all_index = plan.shard_count - 1

    rows =
      Enum.flat_map(shards, fn {index, shard_units, _total} ->
        modules =
          if index == catch_all_index do
            module_inventory
          else
            shard_units |> Enum.map(fn {name, _duration} -> suite_module(name) end) |> Enum.uniq()
          end

        Enum.map(modules, fn module_name ->
          %{
            shard_plan_id: plan.id,
            project_id: project_id,
            shard_index: index,
            module_name: module_name,
            estimated_duration_ms: 0,
            inserted_at: now
          }
        end)
      end)

    if rows != [], do: IngestRepo.insert_all(ShardPlanModule, rows)
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
    plan = ClickHouseRepo.preload(plan, [:test_suites, :modules])
    suite_catch_all? = Keyword.get(opts, :suite_catch_all?, false)

    results =
      plan.test_suites
      |> Enum.filter(&(&1.shard_index == shard_index))
      |> Enum.map(&{&1.module_name, &1.test_suite_name})

    # Each suite shard records the modules it must download (regular shards get their assigned
    # suites' modules; the catch-all gets the full built-module inventory, since it runs every
    # un-skipped target and the shared `.xctestrun` references them all).
    download_modules =
      plan.modules
      |> Enum.filter(&(&1.shard_index == shard_index))
      |> Enum.map(& &1.module_name)
      |> Enum.uniq()

    cond do
      shard_index < 0 or shard_index >= plan.shard_count ->
        nil

      suite_catch_all? and shard_index == plan.shard_count - 1 ->
        skip =
          plan.test_suites
          |> Enum.filter(&(&1.shard_index < shard_index))
          |> Enum.map(&"#{&1.module_name}/#{&1.test_suite_name}")

        %{
          modules: [],
          suites: %{},
          skip: skip,
          download_modules: download_modules_or(download_modules, all_suite_modules(plan))
        }

      results == [] ->
        if shard_index == plan.shard_count - 1 do
          %{
            modules: [],
            suites: %{},
            skip: [],
            download_modules: download_modules_or(download_modules, all_suite_modules(plan))
          }
        end

      true ->
        suites = Enum.group_by(results, fn {mod, _} -> mod end, fn {_, suite} -> suite end)
        modules = Map.keys(suites)
        %{modules: modules, suites: suites, skip: [], download_modules: download_modules_or(download_modules, modules)}
    end
  end

  # Plans created before per-shard download modules were recorded have no `shard_plan_modules` rows
  # for suite shards; fall back so a plan read across a deploy still downloads what it needs.
  defp download_modules_or([], fallback), do: fallback
  defp download_modules_or(download_modules, _fallback), do: download_modules

  defp all_suite_modules(plan), do: plan.test_suites |> Enum.map(& &1.module_name) |> Enum.uniq()

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

  defp get_plan_by_id(project_id, plan_id) do
    ClickHouseRepo.one(
      from(s in ShardPlan,
        where: s.project_id == ^project_id,
        where: s.id == ^plan_id,
        limit: 1
      )
    )
  end

  defp get_shard_for_plan(project, account, plan, shard_index, opts) do
    case fetch_shard_data(plan, shard_index, opts) do
      nil ->
        {:error, :invalid_shard_index}

      %{modules: modules, suites: suites, skip: skip} = shard_data ->
        # The catch-all shard selects nothing via `-only-testing` (`modules` is empty) but must
        # still run every un-skipped target, so it downloads the plan's whole module inventory
        # rather than only its selection modules.
        download_modules = Map.get(shard_data, :download_modules, modules)
        {download_url, download_urls} = shard_download_urls(account, project, plan.id, download_modules)

        {:ok,
         %{
           shard_plan_id: plan.id,
           modules: modules,
           suites: suites,
           skip: skip,
           download_url: download_url,
           download_urls: download_urls
         }}
    end
  end

  defp resolve_units(_project, params, "module"), do: params_modules(params)

  # A client whose products limit a module to specific suites knows exactly what will run for it, so
  # those suites are used as given. Modules it selected nothing for are still resolved from history:
  # a selection usually covers part of a plan, and dropping the rest would hand whole modules to the
  # catch-all shard.
  #
  # Suites the products skip are then dropped from both. A skipped suite cannot run, so planning it
  # gives a shard work that executes nothing, and history is where that happens silently: a suite a
  # test plan disabled stays in the inventory until it ages out of the lookback window. Modules are
  # matched against the pre-skip selection, so a module whose every selected suite is skipped is not
  # resolved from history either: the products limit it to suites that no longer run, and history
  # would answer with ones outside that limit.
  defp resolve_units(project, params, "suite") do
    skipped = MapSet.new(Map.get(params, :skipped_test_suites) || [])
    selected = Map.get(params, :test_suites) || []
    selected_modules = MapSet.new(selected, &suite_module/1)
    unselected_modules = Enum.reject(params_modules(params), &MapSet.member?(selected_modules, &1))

    units = selected ++ latest_branch_suite_units(project, params, unselected_modules)

    Enum.reject(units, &MapSet.member?(skipped, &1))
  end

  defp params_modules(params), do: Map.get(params, :modules) || []

  # The full set of test-target modules the plan covers, used to give the catch-all shard every
  # per-module product it needs to download. The client sends the deterministic `.xctestrun` module
  # universe; when it doesn't (e.g. a client-enumerated suite plan), derive it from the units so the
  # inventory still covers every module that has planned work.
  defp module_inventory(params, units, granularity) do
    case params_modules(params) do
      [_ | _] = modules -> Enum.uniq(modules)
      _ -> units |> Enum.map(&unit_module(&1, granularity)) |> Enum.uniq()
    end
  end

  defp unit_module(unit, "suite"), do: suite_module(unit)
  defp unit_module(unit, _granularity), do: unit

  defp latest_branch_suite_units(_project, _params, []), do: []

  defp latest_branch_suite_units(project, params, modules) do
    modules = Enum.uniq(modules)
    branches = suite_inventory_branches(project, params)

    {units, unresolved} = suite_units(project, branches, modules, :excluded)

    # A run asked for a caller-supplied set of tests executed what it was given, not what the module
    # holds, so it can't stand in for the module's inventory. A module whose only history is such
    # runs still gets one: a partial inventory beats none, because what a plan misses lands on the
    # catch-all shard.
    {restricted_units, _} =
      if unresolved == [], do: {[], []}, else: suite_units(project, branches, unresolved, :included)

    Enum.uniq(units ++ restricted_units)
  end

  # Resolves each module against the preferred branches in order, then falls back to its most recent
  # CI runs on any branch. The preferred branches can come up empty for reasons that have nothing to
  # do with the module: a project that only runs tests on pull-request branches has no history on its
  # default branch, and the build run the branch is read from is written through an async ingestion
  # buffer, so it is usually still unflushed when the plan is created. Without the fallback every
  # module resolves no suites, and a plan with nothing to pack collapses to a single catch-all shard
  # that runs the whole suite serially. Returns the units it resolved and the modules it could not.
  defp suite_units(project, branches, modules, restricted_runs) do
    suites_by_branch_module = latest_branch_module_suite_units(project, branches, modules, restricted_runs)

    units_by_module =
      Map.new(modules, fn module ->
        {module, Enum.find_value(branches, fn branch -> Map.get(suites_by_branch_module, {branch, module}) end)}
      end)

    without_branch_history = for {module, nil} <- units_by_module, do: module
    any_branch_units = latest_module_suite_units(project, without_branch_history, restricted_runs)
    resolved_by_fallback = MapSet.new(any_branch_units, &suite_module/1)
    branch_units = units_by_module |> Map.values() |> Enum.reject(&is_nil/1) |> List.flatten()

    {branch_units ++ any_branch_units, Enum.reject(without_branch_history, &MapSet.member?(resolved_by_fallback, &1))}
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

  defp latest_branch_module_suite_units(_project, [], _modules, _restricted_runs), do: %{}
  defp latest_branch_module_suite_units(_project, _branches, [], _restricted_runs), do: %{}

  defp latest_branch_module_suite_units(project, branches, modules, restricted_runs) do
    query = """
    SELECT branch, module_name, name
    FROM (
      SELECT
        latest.branch AS branch,
        latest.module_name AS module_name,
        concat(mr.name, '/', sr.name) AS name
      FROM test_suite_runs AS sr
      INNER JOIN test_module_runs AS mr ON sr.test_module_run_id = mr.id
      INNER JOIN (
        #{recent_branch_module_runs_query(restricted_runs)}
      ) AS latest
        ON latest.test_run_id = sr.test_run_id
        AND latest.module_name = mr.name
        AND latest.branch = sr.git_branch
      WHERE sr.project_id = {project_id:Int64}
        AND sr.is_ci = true
        AND sr.git_branch IN {branches:Array(String)}
        AND sr.ran_at >= {cutoff:DateTime64(6)}
        AND mr.name IN {modules:Array(String)}
    )
    GROUP BY branch, module_name, name
    """

    {:ok, %{rows: rows}} =
      ClickHouseRepo.query(query, suite_inventory_params(project, modules, branches))

    Enum.group_by(
      rows,
      fn [branch, module_name, _name] -> {branch, module_name} end,
      fn [_branch, _module_name, name] -> name end
    )
  end

  # Suite inventory for modules that have no history on any of the preferred branches, taken from
  # each module's most recent CI runs regardless of branch. Suites that exist only on the branch
  # being built still run: they are absent from the plan, and the catch-all shard picks them up.
  defp latest_module_suite_units(_project, [], _restricted_runs), do: []

  defp latest_module_suite_units(project, modules, restricted_runs) do
    query = """
    SELECT name
    FROM (
      SELECT concat(mr.name, '/', sr.name) AS name
      FROM test_suite_runs AS sr
      INNER JOIN test_module_runs AS mr ON sr.test_module_run_id = mr.id
      INNER JOIN (
        #{recent_module_runs_query(restricted_runs)}
      ) AS latest
        ON latest.test_run_id = sr.test_run_id
        AND latest.module_name = mr.name
      WHERE sr.project_id = {project_id:Int64}
        AND sr.is_ci = true
        AND sr.ran_at >= {cutoff:DateTime64(6)}
        AND mr.name IN {modules:Array(String)}
    )
    GROUP BY name
    """

    {:ok, %{rows: rows}} = ClickHouseRepo.query(query, suite_inventory_params(project, modules))

    Enum.map(rows, fn [name] -> name end)
  end

  # A module's suites are spread across the test runs of the shards that executed them, and those
  # runs are uploaded as each shard finishes, and the catch-all shard, which carries every suite the
  # previous plan didn't know about, finishes last. Reading a single run therefore sees whatever
  # fraction of the module had been ingested when the plan was created, and the suites missing from
  # it are exactly the ones that were already unplanned, so they stay unplanned run after run.
  # Unioning the last few runs restores the module's full inventory, and also covers suites a
  # selective-testing run skipped. The bound keeps a deleted suite from lingering for the whole
  # timing lookback window.
  defp recent_branch_module_runs_query(restricted_runs) do
    """
    SELECT branch, module_name, test_run_id
    FROM (
      #{module_runs_by_recency_query("AND module_runs.git_branch IN {branches:Array(String)}", restricted_runs)}
      LIMIT {runs:UInt8} BY branch, module_name
    )
    """
  end

  defp recent_module_runs_query(restricted_runs) do
    """
    SELECT module_name, test_run_id
    FROM (
      #{module_runs_by_recency_query("", restricted_runs)}
      LIMIT {runs:UInt8} BY module_name
    )
    """
  end

  defp module_runs_by_recency_query(branch_filter, restricted_runs) do
    """
    SELECT
      module_runs.git_branch AS branch,
      module_runs.name AS module_name,
      module_runs.test_run_id AS test_run_id,
      max(module_runs.ran_at) AS ran_at
    FROM test_module_runs AS module_runs
    #{unrestricted_runs_join(restricted_runs)}
    WHERE module_runs.project_id = {project_id:Int64}
      AND module_runs.is_ci = true
      AND module_runs.ran_at >= {cutoff:DateTime64(6)}
      AND module_runs.name IN {modules:Array(String)}
      AND module_runs.test_suite_count > 0
      #{branch_filter}
    GROUP BY branch, module_name, test_run_id
    ORDER BY ran_at DESC
    """
  end

  defp unrestricted_runs_join(:included), do: ""

  # A run the caller limited to specific tests executed what it was given, so its suites are not the
  # module's inventory. One the caller only excluded tests from still ran everything else, and stays
  # evidence: the union across runs covers what it skipped.
  defp unrestricted_runs_join(:excluded) do
    """
    INNER JOIN test_runs AS runs
      ON runs.id = module_runs.test_run_id
      AND runs.project_id = {project_id:Int64}
      AND empty(runs.only_test_identifiers)
    """
  end

  defp suite_inventory_params(project, modules, branches \\ nil) do
    params = %{
      project_id: project.id,
      cutoff: DateTime.add(DateTime.utc_now(), -@timing_lookback_days, :day),
      modules: modules,
      runs: @suite_inventory_runs
    }

    if is_nil(branches), do: params, else: Map.put(params, :branches, branches)
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  # Suite units are named "Module/Suite"; the module prefix is what determines
  # which per-module test bundle a shard needs to download.
  defp suite_module(name) do
    case String.split(name, "/", parts: 2) do
      [module | _] -> module
      _ -> name
    end
  end

  defp fetch_timing_data(_project, _granularity, []), do: %{}

  defp fetch_timing_data(project, "module", modules) do
    cutoff = DateTime.add(DateTime.utc_now(), -@timing_lookback_days, :day)

    from(mr in TestModuleRun,
      where: mr.project_id == ^project.id,
      where: mr.is_ci == true,
      where: mr.ran_at >= ^cutoff,
      where: mr.name in ^modules,
      group_by: mr.name,
      select: %{name: mr.name, duration: fragment("quantile(?)(?)", ^@timing_quantile, mr.duration)}
    )
    |> ClickHouseRepo.all()
    |> Map.new(fn %{name: name, duration: duration} -> {name, round_timing_duration(duration)} end)
  end

  defp fetch_timing_data(project, "suite", units) do
    cutoff = DateTime.add(DateTime.utc_now(), -@timing_lookback_days, :day)
    modules = units |> Enum.map(&suite_module/1) |> Enum.uniq()

    query = """
    SELECT
      concat(mr.name, '/', sr.name) AS name,
      quantile({timing_quantile:Float64})(sr.duration) AS duration
    FROM test_suite_runs AS sr
    INNER JOIN test_module_runs AS mr ON sr.test_module_run_id = mr.id
    WHERE sr.project_id = {project_id:Int64}
      AND sr.is_ci = true
      AND sr.ran_at >= {cutoff:DateTime64(6)}
      AND mr.project_id = {project_id:Int64}
      AND mr.is_ci = true
      AND mr.ran_at >= {cutoff:DateTime64(6)}
      AND mr.name IN {modules:Array(String)}
      AND concat(mr.name, '/', sr.name) IN {units:Array(String)}
    GROUP BY name
    """

    params = %{
      project_id: project.id,
      timing_quantile: @timing_quantile,
      cutoff: cutoff,
      modules: modules,
      units: units
    }

    {:ok, %{rows: rows}} = ClickHouseRepo.query(query, params)

    Map.new(rows, fn [name, duration] -> {name, round_timing_duration(duration)} end)
  end

  defp round_timing_duration(%Decimal{} = duration), do: duration |> Decimal.to_float() |> round()
  defp round_timing_duration(duration), do: round(duration)

  # A suite plan prices a shard as the sum of its suites' durations, which equals the shard's wall
  # clock only when a module runs its suites one after another. Xcode runs a parallelizable module's
  # suites concurrently, so summing them overstates such a module by as much as an order of
  # magnitude, and the bin packer hands a whole shard to work that finishes in a fraction of the
  # budget. Dividing each suite by its module's measured concurrency puts every unit back on the same
  # wall-clock scale before packing.
  #
  # Which modules those are is not inferable from run records: it is a property of the test plan and
  # the `xcodebuild` invocation, and history lags a change to either by the whole lookback window. A
  # module that just stopped running in parallel would keep being divided for a month. So the client
  # declares the set, read from `ParallelizationEnabled` in the `.xctestrun` it is about to run, and
  # history is left to answer only how much concurrency those modules actually achieve. A client that
  # declares nothing gets no scaling.
  defp scale_by_module_parallelism(units_with_durations, _project, _params, "module"), do: units_with_durations

  defp scale_by_module_parallelism(units_with_durations, project, params, "suite") do
    parallelizable = params |> Map.get(:parallelizable_modules) |> List.wrap() |> MapSet.new()

    units_by_module =
      units_with_durations
      |> Enum.group_by(fn {name, _duration} -> suite_module(name) end)
      |> Map.filter(fn {module, _units} -> MapSet.member?(parallelizable, module) end)

    factors =
      units_by_module
      |> Map.keys()
      |> then(&fetch_module_parallelism(project, &1))
      |> Map.new(fn {module, factor} -> {module, cap_factor(factor, Map.fetch!(units_by_module, module))} end)

    Enum.map(units_with_durations, fn {name, duration} ->
      case Map.get(factors, suite_module(name)) do
        nil -> {name, duration}
        factor -> {name, max(round(duration / factor), 1)}
      end
    end)
  end

  # Concurrency is measured over a module's whole suite set, but a plan can hold only part of it,
  # and the suites that are missing are no longer there to overlap with. One suite of a four-way
  # parallel module still takes that suite in full, so a shard's cost for a module can never fall
  # below its longest planned suite. Capping the divisor at the planned set's own spread enforces
  # that bound while leaving a complete inventory on the measured factor.
  defp cap_factor(factor, units) do
    durations = Enum.map(units, fn {_name, duration} -> duration end)
    longest = Enum.max(durations)

    if longest > 0 do
      min(factor, Enum.sum(durations) / longest)
    else
      factor
    end
  end

  # Concurrency is measured per module run as its suites' total duration over its own wall clock,
  # then taken as the median across runs so a single anomalous run cannot move it. A run with one
  # suite carries no concurrency signal, and the ratio is clamped because a module row whose duration
  # was recorded inconsistently with its suites' would otherwise scale that module to near zero.
  #
  # Both tables are `ReplacingMergeTree(inserted_at)` keyed on the row id, so a rewritten row (the
  # `is_flaky` update path) leaves a second physical copy behind until the parts merge. Summing and
  # counting physical rows would inflate a module's suite total, and a duplicate on the module side
  # multiplies through the join into every one of its suites. The innermost grouping folds each row
  # id back to one row first, so neither aggregate can see a duplicate.
  defp fetch_module_parallelism(_project, []), do: %{}

  defp fetch_module_parallelism(project, modules) do
    cutoff = DateTime.add(DateTime.utc_now(), -@timing_lookback_days, :day)

    deduplicated =
      from(sr in TestSuiteRun,
        join: mr in TestModuleRun,
        on: sr.test_module_run_id == mr.id,
        where: sr.project_id == ^project.id,
        where: sr.is_ci == true,
        where: sr.ran_at >= ^cutoff,
        where: mr.project_id == ^project.id,
        where: mr.is_ci == true,
        where: mr.ran_at >= ^cutoff,
        where: mr.name in ^modules,
        group_by: [mr.name, mr.id, sr.id],
        select: %{
          module_name: mr.name,
          module_run_id: mr.id,
          module_duration: fragment("argMax(?, ?)", mr.duration, mr.inserted_at),
          suite_duration: fragment("argMax(?, ?)", sr.duration, sr.inserted_at)
        }
      )

    per_module_run =
      from(d in subquery(deduplicated),
        group_by: [d.module_name, d.module_run_id],
        having: fragment("any(?)", d.module_duration) > 0,
        having: count(d.module_run_id) > 1,
        select: %{
          module_name: d.module_name,
          module_duration: fragment("any(?)", d.module_duration),
          suite_sum: sum(d.suite_duration)
        }
      )

    from(r in subquery(per_module_run),
      group_by: r.module_name,
      select: {r.module_name, fragment("toFloat64(median(? / ?))", r.suite_sum, r.module_duration)}
    )
    |> ClickHouseRepo.all()
    |> Map.new(fn {name, factor} ->
      {name, factor |> max(@min_parallelism_factor) |> min(@max_parallelism_factor)}
    end)
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
