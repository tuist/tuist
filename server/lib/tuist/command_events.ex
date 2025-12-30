defmodule Tuist.CommandEvents do
  @moduledoc ~S"""
  A module for operations related to command events.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.ClickHouseFlop
  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents.Event
  alias Tuist.IngestRepo
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.Time

  def list_command_events(attrs, _opts \\ []) do
    {results, meta} = ClickHouseFlop.validate_and_run!(Event, attrs, for: Event)

    results =
      results
      |> Enum.map(&Event.normalize_enums/1)
      |> attach_user_account_names()

    {results, meta}
  end

  def list_test_runs(attrs) do
    query =
      where(
        Event,
        [e],
        e.name == "test" or
          (e.name == "xcodebuild" and
             (e.subcommand == "test" or e.subcommand == "test-without-building"))
      )

    {results, meta} = ClickHouseFlop.validate_and_run!(query, attrs, for: Event)

    results =
      results
      |> Enum.map(&Event.normalize_enums/1)
      |> attach_user_account_names()

    {results, meta}
  end

  def get_command_events_by_name_git_ref_and_project(attrs, _opts \\ [])

  def get_command_events_by_name_git_ref_and_project(
        %{name: name, git_ref: git_ref, project: %Project{id: project_id}},
        _opts
      ) do
    from(e in Event,
      where:
        e.name == ^name and like(e.git_ref, ^git_ref) and
          e.project_id == ^project_id,
      select: e
    )
    |> ClickHouseRepo.all()
    |> Enum.map(&Event.normalize_enums/1)
  end

  def get_command_event_by_id(id, opts \\ [])

  def get_command_event_by_id(nil, _opts), do: {:error, :not_found}

  def get_command_event_by_id(id, opts) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} ->
        get_command_event_by_id(int_id, opts)

      _ ->
        get_command_event_by_uuid(id, opts)
    end
  end

  def get_command_event_by_id(id, _opts) when is_integer(id) do
    case ClickHouseRepo.one(from(e in Event, where: e.legacy_id == ^id)) do
      nil -> {:error, :not_found}
      event -> {:ok, Event.normalize_enums(event)}
    end
  end

  def get_command_event_by_id(_id, _opts), do: {:error, :not_found}

  defp get_command_event_by_uuid(id, _opts) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         event when not is_nil(event) <-
           ClickHouseRepo.one(from(e in Event, where: e.id == ^uuid)) do
      {:ok, Event.normalize_enums(event)}
    else
      _ ->
        {:error, :not_found}
    end
  end

  def get_user_for_command_event(command_event, opts \\ []) do
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
    {:ok, project} = get_project_for_command_event(command_event, preload: :account)
    Storage.object_exists?(get_result_bundle_key(command_event), project.account)
  end

  def generate_result_bundle_url(command_event) do
    {:ok, project} = get_project_for_command_event(command_event, preload: :account)
    Storage.generate_download_url(get_result_bundle_key(command_event), project.account)
  end

  def get_result_bundle_key(command_event) do
    {:ok, project} = get_project_for_command_event(command_event, preload: :account)
    "#{project.account.name}/#{project.name}/runs/#{command_event.id}/result_bundle.zip"
  end

  def get_result_bundle_invocation_record_key(command_event) do
    {:ok, project} = get_project_for_command_event(command_event, preload: :account)
    "#{project.account.name}/#{project.name}/runs/#{command_event.id}/invocation_record.json"
  end

  def get_result_bundle_object_key(command_event, result_bundle_object_id) do
    {:ok, project} = get_project_for_command_event(command_event, preload: :account)

    "#{project.account.name}/#{project.name}/runs/#{command_event.id}/#{result_bundle_object_id}.json"
  end

  def get_result_bundle_key(run_id, project) do
    "#{get_command_event_artifact_base_path_key(run_id, project)}/result_bundle.zip"
  end

  def get_result_bundle_invocation_record_key(run_id, project) do
    "#{get_command_event_artifact_base_path_key(run_id, project)}/invocation_record.json"
  end

  def get_result_bundle_object_key(run_id, project, result_bundle_object_id) do
    "#{get_command_event_artifact_base_path_key(run_id, project)}/#{result_bundle_object_id}.json"
  end

  def get_command_event_artifact_base_path_key(run_id, project) do
    "#{project.account.name}/#{project.name}/runs/#{run_id}"
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
        created_at: Map.get(event, :created_at, Time.utc_now())
      })

    event_attrs = Event.changeset(processed_event)
    command_event = struct(Event, event_attrs)
    {:ok, _} = Tuist.CommandEvents.Buffer.insert(command_event)

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

  def account_month_usage(account_id, date \\ DateTime.utc_now()) do
    beginning_of_month = Timex.beginning_of_month(date)

    project_ids = Repo.all(from(p in Project, where: p.account_id == ^account_id, select: p.id))

    ClickHouseRepo.one(
      from(c in Event,
        where: c.project_id in ^project_ids,
        where: c.ran_at >= ^beginning_of_month,
        where: c.remote_cache_hits_count > 0 or c.remote_test_hits_count > 0,
        select: %{remote_cache_hits_count: count(c.id)}
      )
    )
  end

  def delete_account_events(account_id) do
    project_ids = Repo.all(from(p in Project, where: p.account_id == ^account_id, select: p.id))
    IngestRepo.delete_all(from(c in Event, where: c.project_id in ^project_ids))
  end

  def list_billable_customers do
    now = DateTime.utc_now()
    start_of_yesterday = now |> Timex.shift(days: -1) |> Timex.beginning_of_day()
    end_of_yesterday = now |> Timex.shift(days: -1) |> Timex.end_of_day()

    from(e in Event,
      where: e.ran_at >= ^start_of_yesterday and e.ran_at <= ^end_of_yesterday,
      group_by: e.project_id,
      select: e.project_id
    )
    |> ClickHouseRepo.all()
    |> case do
      [] ->
        []

      project_ids ->
        Repo.all(
          from(p in Project,
            join: a in Account,
            on: p.account_id == a.id,
            where: p.id in ^project_ids and not is_nil(a.customer_id),
            distinct: a.customer_id,
            select: a.customer_id
          )
        )
    end
  end

  def get_yesterdays_remote_cache_hits_count_for_customer(customer_id) do
    now = DateTime.utc_now()
    start_of_yesterday = now |> Timex.shift(days: -1) |> Timex.beginning_of_day()
    end_of_yesterday = now |> Timex.shift(days: -1) |> Timex.end_of_day()

    from(p in Project,
      join: a in Account,
      on: p.account_id == a.id,
      where: a.customer_id == ^customer_id,
      select: p.id
    )
    |> Repo.all()
    |> case do
      [] ->
        0

      project_ids ->
        ClickHouseRepo.one(
          from(e in Event,
            where:
              e.ran_at >= ^start_of_yesterday and e.ran_at <= ^end_of_yesterday and
                e.project_id in ^project_ids,
            select:
              sum(
                fragment(
                  "CASE WHEN COALESCE(length(?), 0) > 0 OR COALESCE(length(?), 0) > 0 THEN 1 ELSE 0 END",
                  e.remote_cache_target_hits,
                  e.remote_test_target_hits
                )
              )
          )
        )
    end
  end

  def delete_project_events(project_id) do
    IngestRepo.delete_all(from(c in Event, where: c.project_id == ^project_id))
  end

  def get_project_last_interaction_data(project_ids) do
    from(ce in Event,
      where: ce.project_id in ^project_ids,
      group_by: ce.project_id,
      select: %{project_id: ce.project_id, last_interacted_at: max(ce.ran_at)}
    )
    |> ClickHouseRepo.all()
    |> Map.new(fn %{project_id: id, last_interacted_at: time} -> {id, time} end)
  end

  def get_all_project_last_interaction_data do
    from(ce in Event,
      group_by: ce.project_id,
      select: %{project_id: ce.project_id, last_interacted_at: max(ce.ran_at)}
    )
    |> ClickHouseRepo.all()
    |> Map.new(fn %{project_id: id, last_interacted_at: time} -> {id, time} end)
  end

  def get_command_event_by_build_run_id(build_run_id) do
    case ClickHouseRepo.get_by(Event, build_run_id: build_run_id) do
      nil -> {:error, :not_found}
      event -> {:ok, Event.normalize_enums(event)}
    end
  end

  def get_command_event_by_test_run_id(test_run_id) do
    case ClickHouseRepo.get_by(Event, test_run_id: test_run_id) do
      nil -> {:error, :not_found}
      event -> {:ok, Event.normalize_enums(event)}
    end
  end

  def run_events(project_id, start_datetime, end_datetime, opts) do
    query =
      from(e in Event,
        as: :event,
        where:
          e.ran_at > ^DateTime.to_naive(start_datetime) and
            e.ran_at < ^DateTime.to_naive(end_datetime) and
            e.project_id == ^project_id
      )

    query
    |> add_filters(opts)
    |> ClickHouseRepo.all()
    |> Enum.map(&Event.normalize_enums/1)
  end

  def run_average_durations(project_id, start_datetime, end_datetime, date_period, time_bucket, name, opts) do
    date_format = get_date_format(time_bucket)

    date_range_query =
      build_date_range_query(start_datetime, end_datetime, date_period, date_format)

    data_query =
      add_filters(
        from(e in Event,
          as: :event,
          group_by: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
          where:
            e.ran_at > ^DateTime.to_naive(start_datetime) and
              e.ran_at < ^DateTime.to_naive(end_datetime) and e.name == ^name and
              e.project_id == ^project_id,
          select: %{
            date: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
            value: avg(e.duration)
          }
        ),
        Keyword.put(opts, :name, name)
      )

    ClickHouseRepo.all(
      from(dr in subquery(date_range_query),
        left_join: d in subquery(data_query),
        on: dr.date == d.date,
        select: %{date: dr.date, value: fragment("COALESCE(?, 0)", d.value)},
        order_by: dr.date
      )
    )
  end

  def run_count(project_id, start_datetime, end_datetime, date_period, time_bucket, name, opts) do
    date_format = get_date_format(time_bucket)

    date_range_query =
      build_date_range_query(start_datetime, end_datetime, date_period, date_format)

    data_query =
      add_filters(
        from(e in Event,
          as: :event,
          group_by: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
          where:
            e.ran_at > ^DateTime.to_naive(start_datetime) and
              e.ran_at < ^DateTime.to_naive(end_datetime) and
              e.project_id == ^project_id,
          select: %{
            date: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
            count: count(e.id)
          }
        ),
        Keyword.put(opts, :name, name)
      )

    ClickHouseRepo.all(
      from(dr in subquery(date_range_query),
        left_join: d in subquery(data_query),
        on: dr.date == d.date,
        select: %{date: dr.date, count: fragment("COALESCE(?, 0)", d.count)},
        order_by: dr.date
      )
    )
  end

  def cache_hit_rate(project_id, start_datetime, end_datetime, opts) do
    query =
      from(e in Event,
        as: :event,
        where:
          e.project_id == ^project_id and
            e.ran_at > ^DateTime.to_naive(start_datetime) and
            e.ran_at < ^DateTime.to_naive(end_datetime),
        select: %{
          cacheable_targets_count: sum(e.cacheable_targets_count),
          local_cache_hits_count: sum(e.local_cache_hits_count),
          remote_cache_hits_count: sum(e.remote_cache_hits_count)
        }
      )

    query
    |> add_filters(opts)
    |> ClickHouseRepo.one()
  end

  def cache_hit_rates(project_id, start_datetime, end_datetime, _date_period, time_bucket, opts) do
    date_format = get_date_format(time_bucket)

    query =
      from(e in Event,
        as: :event,
        group_by: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
        where:
          e.ran_at > ^DateTime.to_naive(start_datetime) and
            e.ran_at < ^DateTime.to_naive(end_datetime) and
            e.project_id == ^project_id,
        select: %{
          date: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
          cacheable_targets: sum(e.cacheable_targets_count),
          local_cache_target_hits: sum(e.local_cache_hits_count),
          remote_cache_target_hits: sum(e.remote_cache_hits_count)
        }
      )

    query
    |> add_filters(opts)
    |> ClickHouseRepo.all()
  end

  def cache_hit_rate_percentiles(project_id, start_datetime, end_datetime, _date_period, time_bucket, percentile, opts) do
    date_format = get_date_format(time_bucket)

    # For hit rate (higher is better), flip the percentile to get descending order
    # p99 means 99% of runs achieved this hit rate or better
    flipped_percentile = 1 - percentile

    query =
      from(e in Event,
        as: :event,
        group_by: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
        where:
          e.ran_at > ^DateTime.to_naive(start_datetime) and
            e.ran_at < ^DateTime.to_naive(end_datetime) and
            e.project_id == ^project_id and
            e.cacheable_targets_count > 0,
        select: %{
          date: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
          percentile_hit_rate:
            fragment(
              "quantile(?)((? + ?) / ? * 100.0)",
              ^flipped_percentile,
              e.local_cache_hits_count,
              e.remote_cache_hits_count,
              e.cacheable_targets_count
            )
        }
      )

    query
    |> add_filters(opts)
    |> ClickHouseRepo.all()
  end

  def cache_hit_rate_period_percentile(project_id, start_datetime, end_datetime, percentile, opts) do
    # For hit rate (higher is better), flip the percentile to get descending order
    # p99 means 99% of runs achieved this hit rate or better
    flipped_percentile = 1 - percentile

    query =
      from(e in Event,
        as: :event,
        where:
          e.project_id == ^project_id and
            e.ran_at > ^DateTime.to_naive(start_datetime) and
            e.ran_at < ^DateTime.to_naive(end_datetime) and
            e.cacheable_targets_count > 0,
        select:
          fragment(
            "quantile(?)((? + ?) / ? * 100.0)",
            ^flipped_percentile,
            e.local_cache_hits_count,
            e.remote_cache_hits_count,
            e.cacheable_targets_count
          )
      )

    query
    |> add_filters(opts)
    |> ClickHouseRepo.one()
  end

  def selective_testing_hit_rate(project_id, start_datetime, end_datetime, opts) do
    query =
      from(e in Event,
        as: :event,
        where:
          e.project_id == ^project_id and
            e.ran_at > ^DateTime.to_naive(start_datetime) and
            e.ran_at < ^DateTime.to_naive(end_datetime),
        select: %{
          test_targets_count: sum(e.test_targets_count),
          local_test_hits_count: sum(e.local_test_hits_count),
          remote_test_hits_count: sum(e.remote_test_hits_count)
        }
      )

    query
    |> add_filters(opts)
    |> ClickHouseRepo.one()
  end

  def selective_testing_hit_rate_percentiles(project_id, start_datetime, end_datetime, time_bucket, percentile, opts) do
    date_format = get_date_format(time_bucket)

    # For hit rate (higher is better), flip the percentile to get descending order
    # p99 means 99% of runs achieved this hit rate or better
    flipped_percentile = 1 - percentile

    query =
      from(e in Event,
        as: :event,
        group_by: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
        where:
          e.ran_at > ^DateTime.to_naive(start_datetime) and
            e.ran_at < ^DateTime.to_naive(end_datetime) and
            e.project_id == ^project_id and
            e.test_targets_count > 0,
        select: %{
          date: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
          percentile_hit_rate:
            fragment(
              "quantile(?)((? + ?) / ? * 100.0)",
              ^flipped_percentile,
              e.local_test_hits_count,
              e.remote_test_hits_count,
              e.test_targets_count
            )
        }
      )

    query
    |> add_filters(opts)
    |> ClickHouseRepo.all()
  end

  def selective_testing_hit_rate_period_percentile(project_id, start_datetime, end_datetime, percentile, opts) do
    # For hit rate (higher is better), flip the percentile to get descending order
    # p99 means 99% of runs achieved this hit rate or better
    flipped_percentile = 1 - percentile

    query =
      from(e in Event,
        as: :event,
        where:
          e.project_id == ^project_id and
            e.ran_at > ^DateTime.to_naive(start_datetime) and
            e.ran_at < ^DateTime.to_naive(end_datetime) and
            e.test_targets_count > 0,
        select:
          fragment(
            "quantile(?)((? + ?) / ? * 100.0)",
            ^flipped_percentile,
            e.local_test_hits_count,
            e.remote_test_hits_count,
            e.test_targets_count
          )
      )

    query
    |> add_filters(opts)
    |> ClickHouseRepo.one()
  end

  def selective_testing_hit_rates(project_id, start_datetime, end_datetime, _date_period, time_bucket, opts) do
    date_format = get_date_format(time_bucket)

    query =
      from(e in Event,
        as: :event,
        group_by: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
        where:
          e.ran_at > ^DateTime.to_naive(start_datetime) and
            e.ran_at < ^DateTime.to_naive(end_datetime) and
            e.project_id == ^project_id,
        select: %{
          date: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
          test_targets: sum(e.test_targets_count),
          local_test_target_hits: sum(e.local_test_hits_count),
          remote_test_target_hits: sum(e.remote_test_hits_count)
        }
      )

    query
    |> add_filters(opts)
    |> ClickHouseRepo.all()
  end

  def count_events_in_period(start_datetime, end_datetime) do
    ClickHouseRepo.aggregate(
      from(e in Event,
        where:
          e.ran_at >= ^DateTime.to_naive(start_datetime) and
            e.ran_at <= ^DateTime.to_naive(end_datetime)
      ),
      :count
    )
  end

  def count_all_events do
    ClickHouseRepo.aggregate(from(e in Event, []), :count)
  end

  def run_average_duration(project_id, start_datetime, end_datetime, opts) do
    query = build_analytics_query(project_id, start_datetime, end_datetime, opts)

    result =
      query
      |> select([event: e], fragment("avg(?)", e.duration))
      |> ClickHouseRepo.one()

    case result do
      nil -> 0
      duration -> duration
    end
  end

  def run_analytics(project_id, start_datetime, end_datetime, opts) do
    query = build_analytics_query(project_id, start_datetime, end_datetime, opts)

    result =
      query
      |> select([event: e], %{
        total_duration: fragment("sum(?)", e.duration),
        count: fragment("count(*)"),
        average_duration: fragment("avg(?)", e.duration)
      })
      |> ClickHouseRepo.one()

    case result do
      nil ->
        %{total_duration: 0, count: 0, average_duration: 0}

      %{total_duration: nil, count: count, average_duration: nil} ->
        %{total_duration: 0, count: count, average_duration: 0}

      result ->
        result
    end
  end

  defp build_analytics_query(project_id, start_datetime, end_datetime, opts) do
    from(e in Event, as: :event)
    |> where([event: e], e.ran_at > ^DateTime.to_naive(start_datetime))
    |> where([event: e], e.ran_at < ^DateTime.to_naive(end_datetime))
    |> where([event: e], e.project_id == ^project_id)
    |> apply_analytics_filters(opts)
  end

  defp apply_analytics_filters(query, opts) do
    query
    |> apply_is_ci_filter(Keyword.get(opts, :is_ci))
    |> apply_scheme_filter(Keyword.get(opts, :scheme))
    |> apply_category_filter(Keyword.get(opts, :category))
    |> apply_status_filter(Keyword.get(opts, :status))
    |> apply_name_filter_with_alias(Keyword.get(opts, :name))
  end

  defp apply_is_ci_filter(query, nil), do: query
  defp apply_is_ci_filter(query, true), do: where(query, [event: e], e.is_ci == true)
  defp apply_is_ci_filter(query, false), do: where(query, [event: e], e.is_ci == false)

  defp apply_scheme_filter(query, nil), do: query
  defp apply_scheme_filter(query, scheme), do: where(query, [event: e], e.scheme == ^scheme)

  defp apply_category_filter(query, nil), do: query
  defp apply_category_filter(query, category), do: where(query, [event: e], e.category == ^category)

  defp apply_status_filter(query, nil), do: query
  defp apply_status_filter(query, :success), do: where(query, [event: e], e.status == 0)
  defp apply_status_filter(query, :failure), do: where(query, [event: e], e.status == 1)
  defp apply_status_filter(query, _), do: query

  defp apply_name_filter_with_alias(query, "test") do
    where(
      query,
      [event: e],
      (e.name == "xcodebuild" and
         (e.subcommand == "test" or e.subcommand == "test-without-building")) or
        e.name == "test"
    )
  end

  defp apply_name_filter_with_alias(query, _), do: query

  defp add_filters(query, opts) do
    query
    |> query_with_is_ci_filter(opts)
    |> apply_scheme_filter(Keyword.get(opts, :scheme))
    |> apply_category_filter(Keyword.get(opts, :category))
    |> apply_status_filter(Keyword.get(opts, :status))
    |> add_name_filter(opts)
  end

  defp query_with_is_ci_filter(query, opts) do
    apply_is_ci_filter(query, Keyword.get(opts, :is_ci))
  end

  defp add_name_filter(query, opts) do
    apply_name_filter_without_alias(query, Keyword.get(opts, :name))
  end

  defp apply_name_filter_without_alias(query, "test") do
    where(
      query,
      [e],
      (e.name == "xcodebuild" and
         (e.subcommand == "test" or e.subcommand == "test-without-building")) or
        e.name == "test"
    )
  end

  defp apply_name_filter_without_alias(query, _), do: query

  defp get_date_format("1 hour"), do: "%Y-%m-%d %H:00:00"
  defp get_date_format("1 day"), do: "%Y-%m-%d"
  defp get_date_format("1 week"), do: "%Y-%u"
  defp get_date_format("1 month"), do: "%Y-%m"
  defp get_date_format(_), do: "%Y-%m-%d"

  defp build_date_range_query(start_datetime, end_datetime, date_period, date_format) do
    case date_period do
      :hour ->
        start_datetime = DateTime.truncate(start_datetime, :second)
        end_datetime = DateTime.truncate(end_datetime, :second)
        hours_count = max(div(DateTime.diff(end_datetime, start_datetime, :second), 3600) + 1, 1)

        from(
          d in fragment(
            """
              SELECT formatDateTime(
                toDateTime(?) + INTERVAL number HOUR,
                ?
              ) AS date
              FROM numbers(?)
            """,
            ^DateTime.to_naive(start_datetime),
            ^date_format,
            ^hours_count
          ),
          select: %{date: d.date}
        )

      :day ->
        start_date = DateTime.to_date(start_datetime)
        end_date = DateTime.to_date(end_datetime)

        from(
          d in fragment(
            """
              SELECT formatDateTime(
                toDateTime(?) + INTERVAL number DAY,
                ?
              ) AS date
              FROM numbers(dateDiff('day', toDate(?), toDate(?)) + 1)
            """,
            ^DateTime.to_naive(start_datetime),
            ^date_format,
            ^start_date,
            ^end_date
          ),
          select: %{date: d.date}
        )

      :month ->
        start_date = DateTime.to_date(start_datetime)
        end_date = DateTime.to_date(end_datetime)

        from(
          d in fragment(
            """
              SELECT formatDateTime(
                toStartOfMonth(toDateTime(?) + INTERVAL number MONTH),
                ?
              ) AS date
              FROM numbers(dateDiff('month', toDate(?), toDate(?)) + 1)
            """,
            ^NaiveDateTime.new!(Date.beginning_of_month(start_date), ~T[00:00:00]),
            ^date_format,
            ^Date.beginning_of_month(start_date),
            ^Date.beginning_of_month(end_date)
          ),
          select: %{date: d.date}
        )
    end
  end

  defp attach_user_account_names(events) do
    user_ids =
      events
      |> Enum.map(& &1.user_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    user_account_map =
      if Enum.empty?(user_ids) do
        %{}
      else
        user_ids
        |> Tuist.Accounts.list_users_with_accounts_by_ids()
        |> Map.new(&{&1.id, &1.account.name})
      end

    Enum.map(events, fn event ->
      user_account_name = Map.get(user_account_map, event.user_id)
      Map.put(event, :user_account_name, user_account_name)
    end)
  end

  defp build_run_user_map(runs, user_map) do
    Map.new(runs, fn run ->
      user_name = if run.user_id, do: Map.get(user_map, run.user_id)
      {run.id, user_name}
    end)
  end
end
