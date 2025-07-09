defmodule Tuist.CommandEvents do
  @moduledoc ~S"""
  A module for operations related to command events.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents.CacheEvent
  alias Tuist.CommandEvents.Clickhouse
  alias Tuist.CommandEvents.Postgres
  alias Tuist.CommandEvents.ResultBundle.ActionRecord
  alias Tuist.CommandEvents.ResultBundle.ActionResult
  alias Tuist.CommandEvents.ResultBundle.ActionsInvocationRecord
  alias Tuist.CommandEvents.ResultBundle.ActionTestableSummary
  alias Tuist.CommandEvents.ResultBundle.ActionTestMetadata
  alias Tuist.CommandEvents.ResultBundle.ActionTestPlanRunSummaries
  alias Tuist.CommandEvents.ResultBundle.ActionTestPlanRunSummary
  alias Tuist.CommandEvents.ResultBundle.ActionTestSummaryGroup
  alias Tuist.CommandEvents.ResultBundle.Reference
  alias Tuist.CommandEvents.TargetTestSummary
  alias Tuist.CommandEvents.TestCase
  alias Tuist.CommandEvents.TestCaseRun
  alias Tuist.CommandEvents.TestSummary
  alias Tuist.Environment
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.Time
  alias Tuist.Xcode.Clickhouse.XcodeGraph

  defp storage_module do
    if Environment.clickhouse_configured?() and FunWithFlags.enabled?(:clickhouse_events) do
      Clickhouse
    else
      Postgres
    end
  end

  def create_cache_event(
        %{name: name, event_type: event_type, size: size, hash: hash, project_id: project_id},
        attrs \\ []
      ) do
    {:ok, cache_event} =
      Repo.transaction(fn ->
        if is_nil(get_cache_event(%{hash: hash, event_type: event_type})) do
          %CacheEvent{}
          |> CacheEvent.create_changeset(%{
            project_id: project_id,
            name: name,
            hash: hash,
            event_type: event_type,
            size: size,
            created_at: Keyword.get(attrs, :created_at, Time.utc_now())
          })
          |> Repo.insert!()
        end
      end)

    cache_event
  end

  def create_cache_events(cache_events) do
    Repo.insert_all(CacheEvent, cache_events)
  end

  def get_cache_event(%{hash: hash, event_type: event_type}) do
    # Note
    # We should have added a unique index on the hash and event_type columns.
    # However, this was a design mistake, so we are taking the last event as the valid one.
    # In a future iteration, we should delete duplicated rows, and add the unique index.
    Repo.one(
      from c in CacheEvent,
        where: c.hash == ^hash and c.event_type == ^event_type,
        order_by: [desc: :created_at],
        limit: 1
    )
  end

  def list_command_events(attrs, _opts \\ []) do
    storage_module().list_command_events(attrs)
  end

  def list_test_runs(attrs) do
    storage_module().list_test_runs(attrs)
  end

  def get_command_events_by_name_git_ref_and_project(attrs, _opts \\ []) do
    storage_module().get_command_events_by_name_git_ref_and_project(attrs)
  end

  def get_command_event_by_id(id, opts \\ []) do
    storage_module().get_command_event_by_id(id, opts)
  end

  def get_user_for_command_event(command_event, opts \\ []) do
    # NOTE: This should be moved back to `belongs_to` once we remove Postgres backward compatibility and have one `Event` schema.
    preload = Keyword.get(opts, :preload, [])

    with %{user_id: user_id} when not is_nil(user_id) <- command_event,
         user when not is_nil(user) <- Repo.get(User, user_id) do
      user = Repo.preload(user, preload)
      {:ok, user}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_user_account_names_for_runs(runs) do
    case runs |> Enum.map(& &1.user_id) |> Enum.reject(&is_nil/1) do
      user_ids when user_ids != [] ->
        users = Tuist.Accounts.list_users_with_accounts_by_ids(user_ids)
        user_map = Map.new(users, &{&1.id, &1.account.name})

        build_run_user_map(runs, user_map)

      [] ->
        Map.new(runs, &{&1.id, nil})
    end
  end

  def get_project_for_command_event(command_event, opts \\ []) do
    # NOTE: This should be moved back to `belongs_to` once we remove Postgres backward compatibility and have one `Event` schema.
    preload = Keyword.get(opts, :preload, [])

    with %{project_id: project_id} when not is_nil(project_id) <- command_event,
         project when not is_nil(project) <- Repo.get(Project, project_id) do
      project = Repo.preload(project, preload)
      {:ok, project}
    else
      _ -> {:error, :not_found}
    end
  end

  def has_result_bundle?(command_event) do
    Storage.object_exists?(get_result_bundle_key(command_event))
  end

  def generate_result_bundle_url(command_event) do
    Storage.generate_download_url(get_result_bundle_key(command_event))
  end

  def get_result_bundle_key(command_event) do
    "#{get_command_event_artifact_base_path_key(command_event)}/result_bundle.zip"
  end

  def get_result_bundle_invocation_record_key(command_event) do
    "#{get_command_event_artifact_base_path_key(command_event)}/invocation_record.json"
  end

  def get_result_bundle_object_key(command_event, result_bundle_object_id) do
    "#{get_command_event_artifact_base_path_key(command_event)}/#{result_bundle_object_id}.json"
  end

  defp get_command_event_artifact_base_path_key(command_event) do
    project = Repo.get!(Project, command_event.project_id)
    account = Repo.get!(Account, project.account_id)

    identifier =
      if command_event.legacy_artifact_path do
        command_event.legacy_id
      else
        command_event.id
      end

    "#{account.name}/#{project.name}/runs/#{identifier}"
  end

  def list_flaky_test_cases(%Project{} = project, attrs) do
    Flop.validate_and_run!(
      from(t in TestCase,
        where: t.project_id == ^project.id,
        where: t.flaky == true,
        join: t_case_run_1 in TestCaseRun,
        as: :last_flaky_test_case_run,
        on: t_case_run_1.test_case_id == t.id and t_case_run_1.flaky == true,
        preload: [last_flaky_test_case_run: t_case_run_1],
        left_join: t_case_run_2 in TestCaseRun,
        on:
          t_case_run_2.test_case_id == t.id and t_case_run_2.flaky == true and
            t_case_run_1.inserted_at < t_case_run_2.inserted_at,
        select: t
      ),
      attrs,
      for: TestCase
    )
  end

  def list_test_case_runs(attrs) do
    Flop.validate_and_run!(TestCaseRun, attrs, for: TestCaseRun)
  end

  def get_test_case_by_identifier(identifier) do
    Repo.get_by(TestCase, identifier: identifier)
  end

  def create_command_event(event, _opts \\ []) do
    # Process the command arguments to be a string for both databases
    processed_event =
      Map.merge(event, %{
        command_arguments:
          if(is_list(Map.get(event, :command_arguments)),
            do: Enum.join(Map.get(event, :command_arguments), " "),
            else: Map.get(event, :command_arguments)
          ),
        error_message: truncate_error_message(Map.get(event, :error_message)),
        remote_cache_target_hits_count: Map.get(event, :remote_cache_target_hits_count, 0),
        remote_test_target_hits_count: Map.get(event, :remote_test_target_hits_count, 0),
        created_at: Map.get(event, :created_at, Time.utc_now())
      })

    command_event = storage_module().create_command_event(processed_event)

    project = Repo.get!(Project, command_event.project_id)
    account = Repo.get!(Account, project.account_id)

    Tuist.PubSub.broadcast(
      command_event,
      "#{account.name}/#{project.name}",
      :command_event_created
    )

    :telemetry.execute(
      Tuist.Telemetry.event_name_run_command(),
      %{duration: event.duration},
      %{command_event: command_event}
    )

    :telemetry.execute(
      Tuist.Telemetry.event_name_cache(),
      %{
        count:
          length(event.cacheable_targets) - length(event.local_cache_target_hits) -
            length(event.remote_cache_target_hits)
      },
      %{event_type: :miss}
    )

    :telemetry.execute(
      Tuist.Telemetry.event_name_cache(),
      %{count: length(event.local_cache_target_hits)},
      %{event_type: :local_hit}
    )

    :telemetry.execute(
      Tuist.Telemetry.event_name_cache(),
      %{
        count: length(event.remote_cache_target_hits)
      },
      %{event_type: :remote_hit}
    )

    command_event
  end

  defp truncate_error_message(error_message) do
    if not is_nil(error_message) and String.length(error_message) > 255 do
      String.slice(error_message, 0, 240) <> "... (truncated)"
    else
      error_message
    end
  end

  def create_test_case(
        %{
          name: name,
          module_name: module_name,
          identifier: identifier,
          project_identifier: project_identifier,
          project_id: project_id
        },
        attrs \\ []
      ) do
    %TestCase{}
    |> TestCase.create_changeset(%{
      name: name,
      module_name: module_name,
      identifier: identifier,
      project_identifier: project_identifier,
      project_id: project_id,
      flaky: Keyword.get(attrs, :flaky, false),
      inserted_at: Keyword.get(attrs, :inserted_at, Time.utc_now())
    })
    |> Repo.insert!()
  end

  def create_test_case_run(
        %{
          command_event_id: command_event_id,
          test_case_id: test_case_id,
          xcode_target_id: xcode_target_id,
          status: status
        },
        attrs \\ []
      ) do
    %TestCaseRun{}
    |> TestCaseRun.create_changeset(%{
      command_event_id: command_event_id,
      test_case_id: test_case_id,
      xcode_target_id: xcode_target_id,
      status: status,
      flaky: Keyword.get(attrs, :flaky, false),
      inserted_at: Keyword.get(attrs, :inserted_at, Time.utc_now())
    })
    |> Repo.insert!()
  end

  defp get_action_test_plan_run_summaries(action, %{command_event: command_event}) do
    test_plan_summaries_object_key =
      get_result_bundle_object_key(command_event, action.action_result.tests_ref.id)

    if Storage.object_exists?(test_plan_summaries_object_key) do
      test_plan_summaries_string =
        Storage.get_object_as_string(test_plan_summaries_object_key)

      {:ok, test_plan_summaries} = Jason.decode(test_plan_summaries_string)
      get_actions_test_plan_run_summaries(test_plan_summaries)
    else
      %{summaries: []}
    end
  end

  def get_test_summary(%Postgres.Event{} = command_event) do
    do_get_test_summary(command_event)
  end

  def get_test_summary(%Clickhouse.Event{} = command_event) do
    do_get_test_summary(command_event)
  end

  defp do_get_test_summary(command_event) do
    invocation_record_key = get_result_bundle_invocation_record_key(command_event)

    if Storage.object_exists?(invocation_record_key) do
      invocation_record_string = Storage.get_object_as_string(invocation_record_key)
      {:ok, invocation_record} = Jason.decode(invocation_record_string)

      invocation_record = get_actions_invocation_record(invocation_record)

      test_case_run_summaries =
        invocation_record.actions
        |> Enum.filter(fn action -> action.scheme_command_name == "Test" end)
        |> Enum.map(
          &get_action_test_plan_run_summaries(&1, %{
            command_event: command_event
          })
        )
        |> Enum.flat_map(& &1.summaries)

      project_tests =
        test_case_run_summaries
        |> Enum.flat_map(& &1.testable_summaries)
        |> get_project_tests_map()

      all_tests =
        project_tests
        |> Map.values()
        |> Enum.flat_map(&Map.values(&1))
        |> Enum.flat_map(& &1.tests)

      total_tests_count = length(all_tests)

      failed_tests_count =
        all_tests |> Enum.filter(fn test -> test.test_status == :failure end) |> length()

      successful_tests_count = total_tests_count - failed_tests_count

      %TestSummary{
        project_tests: project_tests,
        failed_tests_count: failed_tests_count,
        successful_tests_count: successful_tests_count,
        total_tests_count: total_tests_count
      }
    end
  end

  def create_test_cases(%{test_summary: %TestSummary{} = test_summary, command_event: command_event}) do
    {all_identifiers, all_test_cases} =
      Enum.reduce(test_summary.project_tests, {[], []}, fn {project_identifier, module_tests},
                                                           {acc_identifiers, acc_test_cases} ->
        Enum.reduce(module_tests, {acc_identifiers, acc_test_cases}, fn {module_name, target_test_summary},
                                                                        {identifiers, test_cases} ->
          tests = target_test_summary.tests
          test_identifiers = Enum.map(tests, & &1.identifier_url)

          new_test_cases = build_test_cases(tests, module_name, project_identifier, command_event)

          {identifiers ++ test_identifiers, test_cases ++ new_test_cases}
        end)
      end)

    existing_test_case_identifiers =
      from(
        t in TestCase,
        where: t.identifier in ^all_identifiers
      )
      |> Repo.all()
      |> MapSet.new(& &1.identifier)

    missing_test_cases =
      Enum.reject(all_test_cases, fn test_case ->
        MapSet.member?(existing_test_case_identifiers, test_case.identifier)
      end)

    Repo.insert_all(TestCase, missing_test_cases)
  end

  def create_test_case_runs(%{test_summary: test_summary, command_event: command_event}) do
    # Note:
    # This is currently behind a feature flag due to slow performance inserting thousands of test case runs.
    # Here are some ideas that we could execute on incrementally to get performance gains.
    #
    # 1. Reduce the table size and have a window of two weeks for flakiness detection.
    # 2. Remove foreign keys and keep the indexes to the minimum.
    # 3. Make flakiness flagging a daily job so at API-hit time, it's only the insert time.

    case xcode_data_for_command_event(command_event) do
      {:ok, xcode_data} ->
        test_case_runs = prepare_test_case_runs(test_summary, command_event, xcode_data)
        insert_test_case_runs_and_detect_flaky_tests(test_case_runs)

      :error ->
        :ok
    end
  end

  defp xcode_data_for_command_event(command_event) do
    xcode_graph =
      ClickHouseRepo.one(
        from(xg in XcodeGraph,
          where: xg.command_event_id == ^command_event.id,
          preload: [xcode_projects: :xcode_targets]
        )
      )

    if is_nil(xcode_graph) do
      :error
    else
      targets_by_project =
        Enum.reduce(xcode_graph.xcode_projects, %{}, fn project, acc ->
          Map.put(acc, project.id, project.xcode_targets)
        end)

      {:ok,
       %{
         projects: xcode_graph.xcode_projects,
         targets_by_project: targets_by_project
       }}
    end
  end

  defp prepare_test_case_runs(test_summary, command_event, xcode_data) do
    test_case_identifier_urls = extract_test_case_identifier_urls(test_summary)
    test_case_ids = fetch_test_case_ids(test_case_identifier_urls)

    build_test_case_runs(test_summary, command_event, xcode_data, test_case_ids)
  end

  defp extract_test_case_identifier_urls(test_summary) do
    test_summary.project_tests
    |> Enum.flat_map(fn {_, module_tests} -> Map.values(module_tests) end)
    |> Enum.flat_map(fn target_test_summary -> target_test_summary.tests end)
    |> Enum.map(& &1.identifier_url)
  end

  defp fetch_test_case_ids(test_case_identifier_urls) do
    from(t in TestCase,
      where: t.identifier in ^test_case_identifier_urls,
      select: {t.identifier, t.id}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp build_test_case_runs(test_summary, command_event, xcode_data, test_case_ids) do
    Enum.flat_map(test_summary.project_tests, fn {project_identifier, module_tests} ->
      build_module_test_runs(
        project_identifier,
        module_tests,
        command_event,
        xcode_data,
        test_case_ids
      )
    end)
  end

  defp build_module_test_runs(project_identifier, module_tests, command_event, xcode_data, test_case_ids) do
    Enum.flat_map(module_tests, fn {module_name, target_test_summary} ->
      build_target_test_runs(
        project_identifier,
        module_name,
        target_test_summary,
        command_event,
        xcode_data,
        test_case_ids
      )
    end)
  end

  defp build_target_test_runs(
         project_identifier,
         module_name,
         target_test_summary,
         command_event,
         xcode_data,
         test_case_ids
       ) do
    {project_path, project_name} = parse_project_identifier(project_identifier)
    project = find_project(xcode_data.projects, project_name, project_path)
    target = find_target(xcode_data.targets_by_project, project.id, module_name)

    Enum.map(target_test_summary.tests, fn test_case ->
      {target.id, build_test_case_run_attrs(test_case, command_event, test_case_ids, target.id)}
    end)
  end

  defp parse_project_identifier(project_identifier) do
    case project_identifier
         |> String.trim_trailing(".xcodeproj")
         |> String.split("/") do
      [name] -> {".", name}
      [path, name] -> {path, name}
    end
  end

  defp find_project(projects, name, path) do
    Enum.find(projects, &(&1.name == name && &1.path == path))
  end

  defp find_target(targets_by_project, project_id, module_name) do
    Enum.find(targets_by_project[project_id] || [], &(&1.name == module_name))
  end

  defp build_test_case_run_attrs(test_case, command_event, test_case_ids, target_id) do
    %{
      status: test_case.test_status,
      command_event_id: command_event.id,
      test_case_id: test_case_ids[test_case.identifier_url],
      xcode_target_id: target_id,
      inserted_at: NaiveDateTime.truncate(DateTime.to_naive(Tuist.Time.utc_now()), :second)
    }
  end

  defp insert_test_case_runs_and_detect_flaky_tests(test_case_runs) do
    Repo.transaction(fn ->
      insert_test_case_runs_in_batches(test_case_runs)
      detect_and_mark_flaky_tests(test_case_runs)
    end)
  end

  defp insert_test_case_runs_in_batches(test_case_runs) do
    case List.first(test_case_runs) do
      nil ->
        :ok

      first_test_case_run ->
        # 65535 is the maximum that the PostgreSQL protocol can handle
        # so we divide it by the number of parameters per row, and use that size to determine
        # the chunk size for the inserts
        batch_size = div(65_535, map_size(elem(first_test_case_run, 1)))

        test_case_runs
        |> Enum.chunk_every(batch_size)
        |> Enum.each(fn batch ->
          batch
          |> Enum.map(&elem(&1, 1))
          |> then(&Repo.insert_all(TestCaseRun, &1))
        end)
    end
  end

  defp detect_and_mark_flaky_tests(test_case_runs) do
    xcode_target_ids = Enum.map(test_case_runs, fn {xcode_target_id, _} -> xcode_target_id end)
    flaky_test_case_ids = find_flaky_test_case_ids(xcode_target_ids)
    mark_test_cases_as_flaky(flaky_test_case_ids)
  end

  defp find_flaky_test_case_ids(xcode_target_ids) do
    subquery =
      from(
        t in TestCaseRun,
        where: t.xcode_target_id in ^xcode_target_ids,
        group_by: [t.test_case_id, t.xcode_target_id],
        having: count(fragment("distinct ?", t.status)) > 1,
        select: t.test_case_id
      )

    Repo.all(subquery)
  end

  defp mark_test_cases_as_flaky(flaky_test_case_ids) do
    Repo.update_all(
      from(tcr in TestCaseRun, where: tcr.test_case_id in ^flaky_test_case_ids),
      set: [flaky: true]
    )

    Repo.update_all(
      from(tc in TestCase, where: tc.id in ^flaky_test_case_ids),
      set: [flaky: true]
    )
  end

  defp get_project_tests_map(testable_summaries) do
    Enum.reduce(testable_summaries, %{}, fn testable_summary, tests_map ->
      tests = Enum.flat_map(testable_summary.tests, &get_test_summary_group_tests/1)

      target_test_summary = %TargetTestSummary{
        tests: tests,
        status:
          if Enum.any?(tests, fn test -> test.test_status == :failure end) do
            :failure
          else
            :success
          end
      }

      Map.update(
        tests_map,
        testable_summary.project_identifier,
        %{
          testable_summary.module_name => target_test_summary
        },
        fn project_map ->
          Map.put(project_map, testable_summary.module_name, target_test_summary)
        end
      )
    end)
  end

  defp get_test_summary_group_tests(action_test_summary_group) do
    action_test_summary_group.subtests ++
      Enum.flat_map(action_test_summary_group.subtest_groups, &get_test_summary_group_tests/1)
  end

  defp get_actions_test_plan_run_summaries(json) do
    %ActionTestPlanRunSummaries{
      summaries:
        json
        |> get_result_bundle_array("summaries")
        |> Enum.map(&get_actions_test_plan_run_summary/1)
    }
  end

  defp get_actions_test_plan_run_summary(json) do
    %ActionTestPlanRunSummary{
      testable_summaries:
        json
        |> get_result_bundle_array("testableSummaries")
        |> Enum.map(&get_actions_testable_summary/1)
    }
  end

  defp get_actions_testable_summary(json) do
    %ActionTestableSummary{
      module_name: get_result_bundle_value(json, "targetName"),
      project_identifier: get_result_bundle_value(json, "projectRelativePath"),
      tests:
        json
        |> get_result_bundle_array("tests", type: "ActionTestSummaryGroup")
        |> Enum.map(&get_action_test_summary_group/1)
    }
  end

  defp get_action_test_summary_group(json) do
    %ActionTestSummaryGroup{
      subtests:
        json
        |> get_result_bundle_array("subtests", type: "ActionTestMetadata")
        |> Enum.map(&get_action_test_metadata/1)
        |> Enum.filter(&(not is_nil(&1))),
      subtest_groups:
        json
        |> get_result_bundle_array("subtests", type: "ActionTestSummaryGroup")
        |> Enum.map(&get_action_test_summary_group/1)
    }
  end

  defp get_action_test_metadata(json) do
    test_status =
      case get_result_bundle_value!(json, "testStatus") do
        "Failure" -> :failure
        "Success" -> :success
        _ -> nil
      end

    if is_nil(test_status) do
      nil
    else
      %ActionTestMetadata{
        test_status: test_status,
        name: get_result_bundle_value(json, "name"),
        identifier_url: get_result_bundle_value(json, "identifierURL")
      }
    end
  end

  defp get_actions_invocation_record(json) do
    %ActionsInvocationRecord{
      actions:
        json
        |> get_result_bundle_array("actions")
        |> Enum.map(&get_action_record/1)
    }
  end

  defp get_action_record(json) do
    %ActionRecord{
      scheme_command_name: get_result_bundle_value!(json, "schemeCommandName"),
      action_result: get_action_result(json["actionResult"])
    }
  end

  defp get_action_result(json) do
    %ActionResult{
      tests_ref: get_reference(json["testsRef"])
    }
  end

  defp get_reference(json) do
    %Reference{
      id: get_result_bundle_value(json, "id")
    }
  end

  defp get_result_bundle_value!(json, key) do
    json[key]["_value"]
  end

  defp get_result_bundle_value(json, key) do
    if is_nil(json[key]) do
      nil
    else
      json[key]["_value"]
    end
  end

  defp get_result_bundle_array(json, key, opts \\ []) do
    type = Keyword.get(opts, :type)

    if is_nil(type) do
      get_in(json, [key, "_values"]) || []
    else
      Enum.filter(get_in(json, [key, "_values"]) || [], fn value ->
        value["_type"]["_name"] == type
      end)
    end
  end

  def account_month_usage(account_id, date \\ DateTime.utc_now()) do
    storage_module().account_month_usage(account_id, date)
  end

  def delete_account_events(account_id) do
    storage_module().delete_account_events(account_id)
  end

  def list_customer_id_and_remote_cache_hits_count_pairs(attrs \\ %{}) do
    storage_module().list_customer_id_and_remote_cache_hits_count_pairs(attrs)
  end

  def delete_project_events(project_id) do
    storage_module().delete_project_events(project_id)
  end

  def get_project_last_interaction_data(project_ids) do
    storage_module().get_project_last_interaction_data(project_ids)
  end

  def get_all_project_last_interaction_data do
    storage_module().get_all_project_last_interaction_data()
  end

  def get_command_event_by_build_run_id(build_run_id) do
    storage_module().get_command_event_by_build_run_id(build_run_id)
  end

  def runs_analytics(project_id, start_date, end_date, opts) do
    storage_module().runs_analytics(project_id, start_date, end_date, opts)
  end

  def runs_analytics_average_durations(project_id, start_date, end_date, date_period, time_bucket, name, opts) do
    storage_module().runs_analytics_average_durations(
      project_id,
      start_date,
      end_date,
      date_period,
      time_bucket,
      name,
      opts
    )
  end

  def runs_analytics_count(project_id, start_date, end_date, date_period, time_bucket, name, opts) do
    storage_module().runs_analytics_count(
      project_id,
      start_date,
      end_date,
      date_period,
      time_bucket,
      name,
      opts
    )
  end

  def cache_hit_rate(project_id, start_date, end_date, opts) do
    storage_module().cache_hit_rate(project_id, start_date, end_date, opts)
  end

  def cache_hit_rates(project_id, start_date, end_date, date_period, time_bucket, opts) do
    storage_module().cache_hit_rates(
      project_id,
      start_date,
      end_date,
      date_period,
      time_bucket,
      opts
    )
  end

  def selective_testing_hit_rate(project_id, start_date, end_date, opts) do
    storage_module().selective_testing_hit_rate(project_id, start_date, end_date, opts)
  end

  def selective_testing_hit_rates(project_id, start_date, end_date, date_period, time_bucket, opts) do
    storage_module().selective_testing_hit_rates(
      project_id,
      start_date,
      end_date,
      date_period,
      time_bucket,
      opts
    )
  end

  def count_events_in_period(start_date, end_date) do
    storage_module().count_events_in_period(start_date, end_date)
  end

  def count_all_events do
    storage_module().count_all_events()
  end

  defp build_run_user_map(runs, user_map) do
    Map.new(runs, fn run ->
      user_name = if run.user_id, do: Map.get(user_map, run.user_id)
      {run.id, user_name}
    end)
  end

  defp build_test_cases(tests, module_name, project_identifier, command_event) do
    Enum.map(tests, fn test ->
      %{
        name: test.name,
        module_name: module_name,
        identifier: test.identifier_url,
        project_identifier: project_identifier,
        project_id: command_event.project_id,
        inserted_at: NaiveDateTime.truncate(DateTime.to_naive(Tuist.Time.utc_now()), :second)
      }
    end)
  end
end
