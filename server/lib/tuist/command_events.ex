defmodule Tuist.CommandEvents do
  @moduledoc ~S"""
  A module for operations related to command events.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents.CacheEvent
  alias Tuist.CommandEvents.Event
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
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.Time
  alias Tuist.Xcode.Clickhouse.XcodeGraph

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

  def list_command_events(attrs, opts \\ []) do
    query =
      Event
      |> preload(^Keyword.get(opts, :preload, user: :account))
      |> Event.with_hit_rate()

    preload_preview = opts |> Keyword.get(:preload, []) |> Enum.member?(:preview)

    query =
      if preload_preview do
        query
        |> join(:left, [e], p in assoc(e, :preview), as: :preview)
        |> preload(:preview)
      else
        query
      end

    {hit_rate_filter, other_filters} = extract_hit_rate_filter(attrs)

    query =
      if hit_rate_filter do
        apply_hit_rate_filter_to_query(query, hit_rate_filter)
      else
        query
      end

    {modified_attrs, query} = handle_hit_rate_sort(other_filters, query)

    Flop.validate_and_run!(query, modified_attrs, for: Event)
  end

  defp extract_hit_rate_filter(%{filters: filters} = attrs) when is_list(filters) do
    {hit_rate_filters, other_filters} = Enum.split_with(filters, &(&1.field == :hit_rate))

    hit_rate_filter =
      Enum.find_value(hit_rate_filters, fn
        %{value: value, op: op} when not is_nil(value) -> {op, value}
        _ -> nil
      end)

    {hit_rate_filter, %{attrs | filters: other_filters}}
  end

  defp extract_hit_rate_filter(attrs), do: {nil, attrs}

  defp handle_hit_rate_sort(%{order_by: order_by, order_directions: directions} = attrs, query)
       when is_list(order_by) and is_list(directions) do
    hit_rate_index = Enum.find_index(order_by, &(&1 == :hit_rate))

    if hit_rate_index && hit_rate_index < length(directions) do
      direction = Enum.at(directions, hit_rate_index)

      {new_order_by, new_directions} =
        remove_hit_rate_from_ordering(order_by, directions, hit_rate_index)

      modified_query = apply_hit_rate_ordering(query, direction)

      {%{attrs | order_by: new_order_by, order_directions: new_directions}, modified_query}
    else
      {attrs, query}
    end
  end

  defp handle_hit_rate_sort(attrs, query), do: {attrs, query}

  defp remove_hit_rate_from_ordering(order_by, directions, hit_rate_index) do
    new_order_by = List.delete_at(order_by, hit_rate_index)
    new_directions = List.delete_at(directions, hit_rate_index)

    if Enum.empty?(new_order_by) do
      {[:ran_at], [:desc]}
    else
      {new_order_by, new_directions}
    end
  end

  defp apply_hit_rate_ordering(query, :desc) do
    order_by(
      query,
      [e],
      fragment(
        "CASE WHEN array_length(?, 1) > 0 THEN (COALESCE(array_length(?, 1), 0) + COALESCE(array_length(?, 1), 0))::float / array_length(?, 1) * 100 ELSE NULL END DESC NULLS LAST",
        e.cacheable_targets,
        e.local_cache_target_hits,
        e.remote_cache_target_hits,
        e.cacheable_targets
      )
    )
  end

  defp apply_hit_rate_ordering(query, _direction) do
    order_by(
      query,
      [e],
      fragment(
        "CASE WHEN array_length(?, 1) > 0 THEN (COALESCE(array_length(?, 1), 0) + COALESCE(array_length(?, 1), 0))::float / array_length(?, 1) * 100 ELSE NULL END ASC NULLS FIRST",
        e.cacheable_targets,
        e.local_cache_target_hits,
        e.remote_cache_target_hits,
        e.cacheable_targets
      )
    )
  end

  defp apply_hit_rate_filter_to_query(query, {op, value}) do
    case op do
      :> ->
        where(
          query,
          [e],
          fragment(
            "TRUNC(CAST(CASE WHEN array_length(?, 1) > 0 THEN (COALESCE(array_length(?, 1), 0) + COALESCE(array_length(?, 1), 0))::float / array_length(?, 1) * 100 ELSE 0 END AS NUMERIC), 1) > TRUNC(CAST(? AS NUMERIC), 1)",
            e.cacheable_targets,
            e.local_cache_target_hits,
            e.remote_cache_target_hits,
            e.cacheable_targets,
            ^value
          )
        )

      :>= ->
        where(
          query,
          [e],
          fragment(
            "TRUNC(CAST(CASE WHEN array_length(?, 1) > 0 THEN (COALESCE(array_length(?, 1), 0) + COALESCE(array_length(?, 1), 0))::float / array_length(?, 1) * 100 ELSE 0 END AS NUMERIC), 1) >= TRUNC(CAST(? AS NUMERIC), 1)",
            e.cacheable_targets,
            e.local_cache_target_hits,
            e.remote_cache_target_hits,
            e.cacheable_targets,
            ^value
          )
        )

      :< ->
        where(
          query,
          [e],
          fragment(
            "array_length(?, 1) = 0 OR TRUNC(CAST(? AS NUMERIC), 1) < TRUNC(CAST(? AS NUMERIC), 1)",
            e.cacheable_targets,
            fragment(
              "CASE WHEN array_length(?, 1) > 0 THEN (COALESCE(array_length(?, 1), 0) + COALESCE(array_length(?, 1), 0))::float / array_length(?, 1) * 100 ELSE 0 END",
              e.cacheable_targets,
              e.local_cache_target_hits,
              e.remote_cache_target_hits,
              e.cacheable_targets
            ),
            ^value
          )
        )

      :<= ->
        where(
          query,
          [e],
          fragment(
            "array_length(?, 1) = 0 OR TRUNC(CAST(? AS NUMERIC), 1) <= TRUNC(CAST(? AS NUMERIC), 1)",
            e.cacheable_targets,
            fragment(
              "CASE WHEN array_length(?, 1) > 0 THEN (COALESCE(array_length(?, 1), 0) + COALESCE(array_length(?, 1), 0))::float / array_length(?, 1) * 100 ELSE 0 END",
              e.cacheable_targets,
              e.local_cache_target_hits,
              e.remote_cache_target_hits,
              e.cacheable_targets
            ),
            ^value
          )
        )

      :== ->
        where(
          query,
          [e],
          fragment(
            "TRUNC(CAST(CASE WHEN array_length(?, 1) > 0 THEN (COALESCE(array_length(?, 1), 0) + COALESCE(array_length(?, 1), 0))::float / array_length(?, 1) * 100 ELSE 0 END AS NUMERIC), 1) = TRUNC(CAST(? AS NUMERIC), 1)",
            e.cacheable_targets,
            e.local_cache_target_hits,
            e.remote_cache_target_hits,
            e.cacheable_targets,
            ^value
          )
        )

      _ ->
        query
    end
  end

  def list_test_runs(attrs) do
    query =
      Event
      |> preload(user: :account)
      |> where(
        [e],
        e.name == "test" or
          (e.name == "xcodebuild" and
             (e.subcommand == "test" or e.subcommand == "test-without-building"))
      )

    Flop.validate_and_run!(query, attrs, for: Event)
  end

  def get_command_events_by_name_git_ref_and_project(
        %{name: name, git_ref: git_ref, project: %Project{id: project_id}},
        opts \\ []
      ) do
    preload = Keyword.get(opts, :preload, [])

    from(e in Event,
      where:
        e.name == ^name and e.git_ref == ^git_ref and
          e.project_id == ^project_id,
      select: e
    )
    |> Repo.all()
    |> Repo.preload(preload)
  end

  def get_command_event_by_id(id, opts \\ []) do
    preload = Keyword.get(opts, :preload, user: :account)

    case Event
         |> Repo.get(id)
         |> Repo.preload(preload) do
      nil -> {:error, :not_found}
      command_event -> {:ok, command_event}
    end
  end

  def has_result_bundle?(%Event{} = command_event) do
    Storage.object_exists?(get_result_bundle_key(command_event))
  end

  def generate_result_bundle_url(%Event{} = command_event) do
    Storage.generate_download_url(get_result_bundle_key(command_event))
  end

  def get_result_bundle_key(%Event{} = command_event) do
    command_event = Repo.preload(command_event, project: :account)

    "#{get_command_event_artifact_base_path_key(command_event)}/result_bundle.zip"
  end

  def get_result_bundle_invocation_record_key(%Event{} = command_event) do
    command_event = Repo.preload(command_event, project: :account)

    "#{get_command_event_artifact_base_path_key(command_event)}/invocation_record.json"
  end

  def get_result_bundle_object_key(%Event{} = command_event, result_bundle_object_id) do
    command_event = Repo.preload(command_event, project: :account)

    "#{get_command_event_artifact_base_path_key(command_event)}/#{result_bundle_object_id}.json"
  end

  defp get_command_event_artifact_base_path_key(%Event{} = command_event) do
    command_event = Repo.preload(command_event, project: :account)

    "#{command_event.project.account.name}/#{command_event.project.name}/runs/#{command_event.id}"
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
    TestCaseRun
    |> preload(command_event: [user: :account])
    |> Flop.validate_and_run!(attrs, for: TestCaseRun)
  end

  def get_test_case_by_identifier(identifier) do
    Repo.get_by(TestCase, identifier: identifier)
  end

  def create_command_event(
        %{
          name: name,
          subcommand: subcommand,
          command_arguments: command_arguments,
          duration: duration,
          tuist_version: tuist_version,
          swift_version: swift_version,
          macos_version: macos_version,
          project_id: project_id,
          cacheable_targets: cacheable_targets,
          local_cache_target_hits: local_cache_target_hits,
          remote_cache_target_hits: remote_cache_target_hits,
          test_targets: test_targets,
          local_test_target_hits: local_test_target_hits,
          remote_test_target_hits: remote_test_target_hits,
          is_ci: is_ci,
          user_id: user_id,
          client_id: client_id,
          status: status,
          error_message: error_message,
          preview_id: preview_id,
          git_commit_sha: git_commit_sha,
          git_ref: git_ref,
          git_branch: git_branch,
          ran_at: ran_at,
          build_run_id: build_run_id
        } = event,
        opts \\ []
      ) do
    command_event =
      %Event{}
      |> Event.create_changeset(%{
        name: name,
        subcommand: subcommand,
        command_arguments: Enum.join(command_arguments, " "),
        duration: duration,
        tuist_version: tuist_version,
        swift_version: swift_version,
        macos_version: macos_version,
        project_id: project_id,
        cacheable_targets: cacheable_targets,
        local_cache_target_hits: local_cache_target_hits,
        remote_cache_target_hits: remote_cache_target_hits,
        remote_cache_target_hits_count: Map.get(event, :remote_cache_target_hits_count, 0),
        test_targets: test_targets,
        local_test_target_hits: local_test_target_hits,
        remote_test_target_hits: remote_test_target_hits,
        remote_test_target_hits_count: Map.get(event, :remote_test_target_hits_count, 0),
        is_ci: is_ci,
        user_id: user_id,
        client_id: client_id,
        status: status,
        error_message: truncate_error_message(error_message),
        preview_id: preview_id,
        git_commit_sha: git_commit_sha,
        git_branch: git_branch,
        git_ref: git_ref,
        created_at: Map.get(event, :created_at, Time.utc_now()),
        ran_at: ran_at,
        build_run_id: build_run_id
      })
      |> Repo.insert!()
      |> Repo.preload(Keyword.merge([project: :account], Keyword.get(opts, :preload, [])))

    Tuist.PubSub.broadcast(
      command_event,
      "#{command_event.project.account.name}/#{command_event.project.name}",
      :command_event_created
    )

    :telemetry.execute(
      Tuist.Telemetry.event_name_run_command(),
      %{duration: duration},
      %{command_event: command_event}
    )

    :telemetry.execute(
      Tuist.Telemetry.event_name_cache(),
      %{
        count:
          length(cacheable_targets) - length(local_cache_target_hits) -
            length(remote_cache_target_hits)
      },
      %{event_type: :miss}
    )

    :telemetry.execute(
      Tuist.Telemetry.event_name_cache(),
      %{count: length(local_cache_target_hits)},
      %{event_type: :local_hit}
    )

    :telemetry.execute(
      Tuist.Telemetry.event_name_cache(),
      %{
        count: length(remote_cache_target_hits)
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

  def get_test_summary(%Event{} = command_event) do
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
    map_project_tests(test_summary.project_tests, fn %{
                                                       project_identifier: project_identifier,
                                                       module_name: module_name,
                                                       target_test_summary: target_test_summary
                                                     } ->
      tests = target_test_summary.tests
      identifiers = Enum.map(tests, & &1.identifier_url)

      existing_test_case_identifiers =
        from(
          t in TestCase,
          where: t.identifier in ^identifiers
        )
        |> Repo.all()
        |> MapSet.new(& &1.identifier)

      missing_test_cases =
        tests
        |> Enum.reject(fn test ->
          MapSet.member?(existing_test_case_identifiers, test.identifier_url)
        end)
        |> Enum.map(fn test ->
          %{
            name: test.name,
            module_name: module_name,
            identifier: test.identifier_url,
            project_identifier: project_identifier,
            project_id: command_event.project_id,
            inserted_at: NaiveDateTime.truncate(DateTime.to_naive(Tuist.Time.utc_now()), :second)
          }
        end)

      Repo.insert_all(TestCase, missing_test_cases)
    end)
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

  defp map_project_tests(project_tests, map_f) do
    Enum.each(project_tests, fn {project_identifier, module_tests} ->
      Enum.each(module_tests, fn {module_name, target_test_summary} ->
        map_f.(%{
          project_identifier: project_identifier,
          module_name: module_name,
          target_test_summary: target_test_summary
        })
      end)
    end)
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
end
