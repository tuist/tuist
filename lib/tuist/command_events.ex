defmodule Tuist.CommandEvents do
  @moduledoc ~S"""
  A module for operations related to command events.
  """
  alias Tuist.CommandEvents.TestCase
  alias Tuist.CommandEvents.TestCaseRun
  alias Tuist.CommandEvents.TargetTestSummary
  alias Tuist.CommandEvents.TestSummary

  alias Tuist.CommandEvents.ResultBundle.{
    ActionTestSummaryGroup,
    Reference,
    ActionTestableSummary,
    ActionTestPlanRunSummary,
    ActionTestPlanRunSummaries,
    ActionResult,
    ActionsInvocationRecord,
    ActionRecord,
    ActionTestMetadata
  }

  alias Tuist.Storage
  alias Tuist.Projects.Project
  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.CommandEvents.CacheEvent
  alias Tuist.CommandEvents.Event
  alias Tuist.Time
  import Ecto.Query
  import Timescale.Hyperfunctions

  def create_cache_event(
        %{
          name: name,
          event_type: event_type,
          size: size,
          hash: hash,
          project_id: project_id
        },
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

  def update_cache_event_counts() do
    start_date = DateTime.add(Time.utc_now(), -30, :day)

    query =
      from(
        a in Account,
        join: p in Project,
        on: a.id == p.account_id,
        join: c in CacheEvent,
        on: c.project_id == p.id,
        where: c.created_at > ^start_date,
        group_by: [a.id, c.event_type],
        select: {a, c.event_type, count(c.id)}
      )

    Repo.transaction(fn ->
      query
      |> Repo.stream()
      |> Stream.each(&update_cache_event_count/1)
      |> Stream.run()
    end)
  end

  defp update_cache_event_count({account, event_type, count}) do
    case event_type do
      :download ->
        Repo.update(account |> Ecto.Changeset.change(cache_download_event_count: count))

      :upload ->
        Repo.update(account |> Ecto.Changeset.change(cache_upload_event_count: count))
    end
  end

  def list_command_events(attrs) do
    Event
    |> preload(user: :account)
    |> Flop.validate_and_run!(attrs)
  end

  def get_command_event_by_id(id, opts \\ []) do
    preloads = opts |> Keyword.get(:preloads, user: :account)

    Repo.get(Event, id)
    |> Repo.preload(preloads)
  end

  def has_result_bundle?(%Event{} = command_event) do
    Storage.object_exists?(get_result_bundle_key(command_event))
  end

  def generate_result_bundle_url(%Event{} = command_event) do
    Storage.generate_download_url(get_result_bundle_key(command_event))
  end

  def get_result_bundle_key(%Event{} = command_event) do
    command_event = command_event |> Repo.preload(project: :account)

    "#{get_command_event_artifact_base_path_key(command_event)}/result_bundle.zip"
  end

  def get_result_bundle_invocation_record_key(%Event{} = command_event) do
    command_event = command_event |> Repo.preload(project: :account)

    "#{get_command_event_artifact_base_path_key(command_event)}/invocation_record.json"
  end

  def get_result_bundle_object_key(%Event{} = command_event, result_bundle_object_id) do
    command_event = command_event |> Repo.preload(project: :account)

    "#{get_command_event_artifact_base_path_key(command_event)}/#{result_bundle_object_id}.json"
  end

  defp get_command_event_artifact_base_path_key(%Event{} = command_event) do
    command_event = command_event |> Repo.preload(project: :account)

    "#{command_event.project.account.name}/#{command_event.project.name}/runs/#{command_event.id}"
  end

  def get_command_duration_analytics(
        name,
        opts
      ) do
    project_id = Keyword.get(opts, :project_id)
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(Time.utc_now()))
    is_ci = Keyword.get(opts, :is_ci)

    days_delta = Date.diff(end_date, start_date)

    date_period = date_period(start_date: start_date, end_date: end_date)

    previous_total_average_duration =
      get_total_command_period_average_duration(
        name,
        project_id,
        start_date: Date.add(start_date, -days_delta),
        end_date: start_date
      )

    total_average_duration =
      get_total_command_period_average_duration(
        name,
        project_id,
        start_date: start_date,
        end_date: end_date,
        is_ci: is_ci
      )

    average_durations =
      get_command_average(
        name,
        project_id,
        start_date: start_date,
        end_date: end_date,
        date_period: date_period,
        is_ci: is_ci
      )

    %{
      trend:
        get_trend(
          previous_value: previous_total_average_duration,
          current_value: total_average_duration
        ),
      total_average_duration: total_average_duration,
      average_durations: average_durations,
      dates:
        get_formatted_dates(
          Enum.map(
            average_durations,
            & &1.date
          ),
          date_period
        ),
      values:
        Enum.map(
          average_durations,
          & &1.average
        )
    }
  end

  def list_flaky_test_cases(%Project{} = project, attrs) do
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
    )
    |> Flop.validate_and_run!(attrs, for: TestCase)
  end

  def list_test_case_runs(attrs) do
    TestCaseRun
    |> preload(command_event: [user: :account])
    |> Flop.validate_and_run!(attrs, for: TestCaseRun)
  end

  def get_test_case_by_identifier(identifier) do
    Repo.get_by(TestCase, identifier: identifier)
  end

  def get_command_runs_analytics(name, opts) do
    project_id = Keyword.get(opts, :project_id)
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(Time.utc_now()))
    days_diff = Date.diff(end_date, start_date)

    date_period = date_period(start_date: start_date, end_date: end_date)

    previous_command_runs =
      get_command_runs(
        name,
        project_id: project_id,
        start_date: Date.add(start_date, -days_diff),
        end_date: start_date,
        date_period: date_period
      )

    command_runs =
      get_command_runs(
        name,
        project_id: project_id,
        start_date: start_date,
        end_date: end_date,
        date_period: date_period
      )

    runs_count = Enum.sum(Enum.map(command_runs, & &1.count))

    %{
      trend:
        get_trend(
          previous_value: Enum.sum(Enum.map(previous_command_runs, & &1.count)),
          current_value: runs_count
        ),
      runs_count: runs_count,
      values:
        Enum.map(
          command_runs,
          & &1.count
        ),
      dates:
        get_formatted_dates(
          Enum.map(
            command_runs,
            & &1.date
          ),
          date_period
        )
    }
  end

  defp get_command_runs(name, opts) do
    project_id = Keyword.get(opts, :project_id)
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(Time.utc_now()))
    date_period = opts |> Keyword.get(:date_period)

    time_bucket = time_bucket_for_date_period(date_period)

    command_run_counts_all =
      Repo.all(
        from e in Event,
          group_by: selected_as(^date_period),
          where:
            e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
              e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and e.name == ^name and
              e.project_id == ^project_id,
          select: %{
            date: selected_as(time_bucket(e.created_at, ^time_bucket), ^date_period),
            count: count(e)
          }
      )

    command_run_counts =
      command_run_counts_all
      |> Map.new(&{normalise_date(&1.date, date_period), &1.count})

    date_range_for_date_period(date_period, start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      count = Map.get(command_run_counts, date)

      %{
        date: date,
        count:
          if is_nil(count) do
            0
          else
            count
          end
      }
    end)
  end

  @doc """
  Returns the trend between the current value and the previous value as a percentage value. The value is negative if the current_value is smaller than previous_value.

  Returns 0 if the previous value is 0 or if the current value is 0.
  """
  def get_trend(opts) do
    previous_value = Keyword.get(opts, :previous_value)
    current_value = Keyword.get(opts, :current_value)

    case {previous_value, current_value} do
      {0, _} ->
        0.0

      {_, 0} ->
        0.0

      {+0.0, _} ->
        0.0

      {_, +0.0} ->
        0.0

      {previous_value, current_value} ->
        Float.round(
          current_value / previous_value * 100,
          1
        ) - 100.0
    end
  end

  def get_total_command_period_average_duration(
        name,
        project_id,
        opts \\ []
      ) do
    start_date = Keyword.get(opts, :start_date, Date.add(Time.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(Time.utc_now()))

    average =
      from(e in Event,
        where:
          e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and e.name == ^name and
            e.project_id == ^project_id
      )
      |> add_filters(opts)
      |> Repo.aggregate(:avg, :duration)

    if is_nil(average) do
      0
    else
      Decimal.to_float(average)
    end
  end

  defp get_command_average(
         name,
         project_id,
         opts
       ) do
    start_date = opts |> Keyword.get(:start_date, Date.add(Time.utc_now(), -30))
    end_date = opts |> Keyword.get(:end_date, DateTime.to_date(Time.utc_now()))
    date_period = opts |> Keyword.get(:date_period, :day)

    time_bucket = time_bucket_for_date_period(date_period)

    command_averages =
      from(e in Event,
        group_by: selected_as(^date_period),
        where:
          e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and e.name == ^name and
            e.project_id == ^project_id,
        select: %{
          date: selected_as(time_bucket(e.created_at, ^time_bucket), ^date_period),
          average: avg(e.duration)
        }
      )
      |> add_filters(opts)
      |> Repo.all()
      |> Map.new(&{normalise_date(&1.date, date_period), &1.average})

    date_range_for_date_period(date_period, start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      average = Map.get(command_averages, date)

      %{
        date: date,
        average:
          if is_nil(average) do
            0
          else
            Decimal.to_float(average)
          end
      }
    end)
  end

  def get_cache_hit_rate_analytics(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    start_date = Keyword.get(opts, :start_date, Date.add(Time.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(Time.utc_now()))
    is_ci = Keyword.get(opts, :is_ci)

    days_delta = Date.diff(end_date, start_date)

    date_period = date_period(start_date: start_date, end_date: end_date)

    current_cache_hit_rate =
      get_cache_hit_rate(
        project_id,
        start_date: start_date,
        end_date: end_date,
        is_ci: is_ci
      )

    previous_cache_hit_rate =
      get_cache_hit_rate(
        project_id,
        start_date: Date.add(start_date, -days_delta),
        end_date: start_date,
        is_ci: is_ci
      )

    cache_hit_rates =
      get_cache_hit_rates(project_id,
        start_date: start_date,
        end_date: end_date,
        date_period: date_period,
        is_ci: is_ci
      )

    %{
      trend:
        get_trend(
          previous_value: previous_cache_hit_rate,
          current_value: current_cache_hit_rate
        ),
      cache_hit_rate: current_cache_hit_rate,
      dates:
        get_formatted_dates(
          Enum.map(
            cache_hit_rates,
            & &1.date
          ),
          date_period
        ),
      values:
        Enum.map(
          cache_hit_rates,
          & &1.cache_hit_rate
        )
    }
  end

  defp get_cache_hit_rates(project_id, opts) do
    start_date = opts |> Keyword.get(:start_date)
    end_date = opts |> Keyword.get(:end_date)
    date_period = opts |> Keyword.get(:date_period)

    time_bucket = time_bucket_for_date_period(date_period)

    cache_hit_rate_metadata_map =
      from(e in Event,
        group_by: selected_as(^date_period),
        where:
          e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and
            e.project_id == ^project_id,
        select: %{
          date: selected_as(time_bucket(e.created_at, ^time_bucket), ^date_period),
          cacheable_targets: sum(fragment("array_length(?, 1)", e.cacheable_targets)),
          local_cache_target_hits: sum(fragment("array_length(?, 1)", e.local_cache_target_hits)),
          remote_cache_target_hits:
            sum(fragment("array_length(?, 1)", e.remote_cache_target_hits))
        }
      )
      |> add_filters(opts)
      |> Repo.all()
      |> Map.new(
        &{normalise_date(&1.date, date_period),
         %{
           cacheable_targets: &1.cacheable_targets,
           local_cache_target_hits: &1.local_cache_target_hits,
           remote_cache_target_hits: &1.remote_cache_target_hits
         }}
      )

    date_range_for_date_period(date_period, start_date: start_date, end_date: end_date)
    |> Enum.map(fn date ->
      cache_hit_rate_metadata = Map.get(cache_hit_rate_metadata_map, date)

      if is_nil(cache_hit_rate_metadata) or (cache_hit_rate_metadata.cacheable_targets || 0) == 0 do
        %{
          date: date,
          cache_hit_rate: 0
        }
      else
        cacheable_targets = cache_hit_rate_metadata.cacheable_targets
        local_cache_target_hits = cache_hit_rate_metadata.local_cache_target_hits || 0
        remote_cache_target_hits = cache_hit_rate_metadata.remote_cache_target_hits || 0

        %{
          date: date,
          cache_hit_rate: (local_cache_target_hits + remote_cache_target_hits) / cacheable_targets
        }
      end
    end)
  end

  defp get_cache_hit_rate(project_id, opts) do
    start_date = opts |> Keyword.get(:start_date, Date.add(Time.utc_now(), -30))
    end_date = DateTime.to_date(Time.utc_now())

    result =
      from(e in Event,
        where:
          e.project_id == ^project_id and
            e.created_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.created_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]),
        select: %{
          cacheable_targets_count: sum(fragment("array_length(?, 1)", e.cacheable_targets)),
          local_cache_target_hits_count:
            sum(fragment("array_length(?, 1)", e.local_cache_target_hits)),
          remote_cache_target_hits_count:
            sum(fragment("array_length(?, 1)", e.remote_cache_target_hits))
        }
      )
      |> add_filters(opts)
      |> Repo.one()

    local_cache_target_hits_count = result.local_cache_target_hits_count || 0
    remote_cache_target_hits_count = result.remote_cache_target_hits_count || 0
    cacheable_targets_count = result.cacheable_targets_count || 0

    if cacheable_targets_count == 0 do
      0
    else
      (local_cache_target_hits_count + remote_cache_target_hits_count) / cacheable_targets_count
    end
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
          error_message: error_message
        },
        attrs \\ []
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
        test_targets: test_targets,
        local_test_target_hits: local_test_target_hits,
        remote_test_target_hits: remote_test_target_hits,
        is_ci: is_ci,
        user_id: user_id,
        client_id: client_id,
        status: status,
        error_message: error_message |> truncate_error_message(),
        created_at: Keyword.get(attrs, :created_at, Time.utc_now())
      })
      |> Repo.insert!()

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
          module_hash: module_hash,
          test_case_id: test_case_id,
          status: status
        },
        attrs \\ []
      ) do
    query =
      from(
        t1 in TestCaseRun,
        join: t2 in TestCaseRun,
        on: t1.test_case_id == t2.test_case_id,
        where: t1.status != t2.status and t1.module_hash == ^module_hash
      )

    %TestCaseRun{}
    |> TestCaseRun.create_changeset(%{
      module_hash: module_hash,
      command_event_id: command_event_id,
      test_case_id: test_case_id,
      status: status,
      flaky: Keyword.get(attrs, :flaky, Repo.exists?(query)),
      inserted_at: Keyword.get(attrs, :inserted_at, Time.utc_now())
    })
    |> Repo.insert!()
  end

  defp get_action_test_plan_run_summaries(action, %{
         command_event: command_event
       }) do
    test_plan_summaries_object_key =
      get_result_bundle_object_key(command_event, action.action_result.tests_ref.id)

    if Storage.object_exists?(test_plan_summaries_object_key) do
      {:ok, test_plan_summaries_string} =
        Storage.get_object_as_string(test_plan_summaries_object_key)

      {:ok, test_plan_summaries} = test_plan_summaries_string |> Jason.decode()
      test_plan_summaries |> get_actions_test_plan_run_summaries()
    else
      %{summaries: []}
    end
  end

  def get_test_summary(%Event{} = command_event) do
    invocation_record_key = get_result_bundle_invocation_record_key(command_event)

    if Storage.object_exists?(invocation_record_key) do
      {:ok, invocation_record_string} = Storage.get_object_as_string(invocation_record_key)
      {:ok, invocation_record} = invocation_record_string |> Jason.decode()

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
        Map.values(project_tests)
        |> Enum.flat_map(&Map.values(&1))
        |> Enum.flat_map(& &1.tests)

      total_tests_count = length(all_tests)

      failed_tests_count =
        Enum.filter(all_tests, fn test -> test.test_status == :failure end) |> length

      successful_tests_count = total_tests_count - failed_tests_count

      %TestSummary{
        project_tests: project_tests,
        failed_tests_count: failed_tests_count,
        successful_tests_count: successful_tests_count,
        total_tests_count: total_tests_count
      }
    else
      nil
    end
  end

  def create_test_cases(%{
        test_summary: %TestSummary{} = test_summary,
        command_event: command_event
      }) do
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
        |> Enum.map(& &1.identifier)
        |> MapSet.new()

      missing_test_cases =
        Enum.reject(tests, fn test ->
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

  def create_test_case_runs(%{
        test_summary: test_summary,
        modules: modules,
        command_event: command_event
      }) do
    map_project_tests(test_summary.project_tests, fn %{
                                                       project_identifier: project_identifier,
                                                       module_name: module_name,
                                                       target_test_summary: target_test_summary
                                                     } ->
      tests = target_test_summary.tests

      identifiers = Enum.map(tests, & &1.identifier_url)

      test_case_ids =
        from(
          t in TestCase,
          where: t.identifier in ^identifiers
        )
        |> Repo.all()
        |> Map.new(&{&1.identifier, &1.id})

      test_case_runs =
        Enum.map(tests, fn test ->
          %{
            module_hash: modules[project_identifier][module_name],
            command_event_id: command_event.id,
            status: test.test_status,
            test_case_id: test_case_ids[test.identifier_url],
            inserted_at: NaiveDateTime.truncate(DateTime.to_naive(Tuist.Time.utc_now()), :second)
          }
        end)

      Repo.insert_all(TestCaseRun, test_case_runs)

      from(
        t1 in TestCaseRun,
        join: t2 in TestCaseRun,
        on: t1.test_case_id == t2.test_case_id,
        where: t1.module_hash == t2.module_hash and t1.status != t2.status
      )
      |> Repo.update_all(set: [flaky: true])

      from(
        t in TestCase,
        join: test_case_run in TestCaseRun,
        on: t.id == test_case_run.test_case_id,
        where: test_case_run.flaky == true,
        select: t
      )
      |> Repo.update_all(set: [flaky: true])
    end)
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
    testable_summaries
    |> Enum.reduce(%{}, fn testable_summary, tests_map ->
      tests =
        testable_summary.tests
        |> Enum.flat_map(&get_test_summary_group_tests/1)

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
        get_result_bundle_array(json, "summaries")
        |> Enum.map(&get_actions_test_plan_run_summary/1)
    }
  end

  defp get_actions_test_plan_run_summary(json) do
    %ActionTestPlanRunSummary{
      testable_summaries:
        get_result_bundle_array(json, "testableSummaries")
        |> Enum.map(&get_actions_testable_summary/1)
    }
  end

  defp get_actions_testable_summary(json) do
    %ActionTestableSummary{
      module_name: get_result_bundle_value(json, "targetName"),
      project_identifier: get_result_bundle_value(json, "projectRelativePath"),
      tests:
        get_result_bundle_array(json, "tests", type: "ActionTestSummaryGroup")
        |> Enum.map(&get_action_test_summary_group/1)
    }
  end

  defp get_action_test_summary_group(json) do
    %ActionTestSummaryGroup{
      subtests:
        get_result_bundle_array(json, "subtests", type: "ActionTestMetadata")
        |> Enum.map(&get_action_test_metadata/1)
        |> Enum.filter(&(not is_nil(&1))),
      subtest_groups:
        get_result_bundle_array(json, "subtests", type: "ActionTestSummaryGroup")
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
        get_result_bundle_array(json, "actions")
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
      json[key]["_values"]
    else
      json[key]["_values"]
      |> Enum.filter(fn value -> value["_type"]["_name"] == type end)
    end
  end

  defp date_period(opts) do
    start_date = opts |> Keyword.get(:start_date)
    end_date = opts |> Keyword.get(:end_date)
    days_delta = Date.diff(end_date, start_date)

    if days_delta >= 60 do
      :month
    else
      :day
    end
  end

  defp get_formatted_dates(dates, date_period) do
    Enum.map(
      dates,
      case date_period do
        :month ->
          &Calendar.strftime(&1, "%b %Y")

        :day ->
          &Calendar.strftime(&1, "%b %d")
      end
    )
  end

  defp time_bucket_for_date_period(date_period) do
    case date_period do
      :day -> %Postgrex.Interval{days: 1}
      :month -> %Postgrex.Interval{months: 1}
    end
  end

  defp date_range_for_date_period(date_period, opts) do
    start_date = opts |> Keyword.get(:start_date)
    end_date = opts |> Keyword.get(:end_date)

    Date.range(start_date, end_date)
    |> Enum.filter(fn date ->
      case date_period do
        :month ->
          date.day == 1

        :day ->
          true
      end
    end)
  end

  defp normalise_date(naive_datetime, date_period) do
    date = NaiveDateTime.to_date(naive_datetime)

    case date_period do
      :day -> date
      :month -> Date.beginning_of_month(date)
    end
  end

  defp add_filters(query, opts) do
    is_ci = Keyword.get(opts, :is_ci)

    case is_ci do
      nil -> query
      true -> where(query, [e], e.is_ci == true)
      false -> where(query, [e], e.is_ci == false)
    end
  end
end
