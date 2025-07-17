defmodule Tuist.CommandEvents.Clickhouse do
  @moduledoc ~S"""
  ClickHouse-specific implementation for command events operations.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.ClickHouseFlop
  alias Tuist.ClickHouseRepo
  alias Tuist.CommandEvents.Clickhouse.Event
  alias Tuist.Projects.Project
  alias Tuist.Repo

  def list_command_events(attrs) do
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

  def get_command_events_by_name_git_ref_and_project(%{name: name, git_ref: git_ref, project: %Project{id: project_id}}) do
    from(e in Event,
      where:
        e.name == ^name and e.git_ref == ^git_ref and
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

  def create_command_event(event_attrs) do
    event_attrs = Event.changeset(event_attrs)

    event = struct(Event, event_attrs)
    {:ok, command_event} = ClickHouseRepo.insert(event)
    Event.normalize_enums(command_event)
  end

  def account_month_usage(account_id, date \\ DateTime.utc_now()) do
    beginning_of_month = Timex.beginning_of_month(date)

    project_ids = Repo.all(from(p in Project, where: p.account_id == ^account_id, select: p.id))

    ClickHouseRepo.one(
      from(c in Event,
        where: c.project_id in ^project_ids,
        where: c.ran_at >= ^beginning_of_month,
        where: c.remote_cache_target_hits_count > 0 or c.remote_test_target_hits_count > 0,
        select: %{remote_cache_hits_count: count(c.id)}
      )
    )
  end

  def delete_account_events(account_id) do
    project_ids = Repo.all(from(p in Project, where: p.account_id == ^account_id, select: p.id))
    ClickHouseRepo.delete_all(from(c in Event, where: c.project_id in ^project_ids))
  end

  def list_customer_id_and_remote_cache_hits_count_pairs(attrs \\ %{}) do
    now = DateTime.utc_now()
    start_of_yesterday = now |> Timex.shift(days: -1) |> Timex.beginning_of_day()
    end_of_yesterday = now |> Timex.shift(days: -1) |> Timex.end_of_day()

    project_customer_pairs =
      from(a in Account,
        join: p in Project,
        on: p.account_id == a.id,
        where: not is_nil(a.customer_id),
        select: {p.id, a.customer_id}
      )
      |> Repo.all()
      |> Map.new()

    if Enum.empty?(project_customer_pairs) do
      {[], %{}}
    else
      project_ids = Map.keys(project_customer_pairs)

      query =
        from(e in Event,
          where:
            e.ran_at >= ^start_of_yesterday and e.ran_at <= ^end_of_yesterday and
              e.project_id in ^project_ids,
          group_by: e.project_id,
          select: %{
            project_id: e.project_id,
            count:
              sum(
                fragment(
                  "CASE WHEN COALESCE(length(?), 0) > 0 OR COALESCE(length(?), 0) > 0 THEN 1 ELSE 0 END",
                  e.remote_cache_target_hits,
                  e.remote_test_target_hits
                )
              )
          }
        )

      {events_by_project, meta} = ClickHouseFlop.validate_and_run!(query, attrs, for: Event)

      customer_counts =
        events_by_project
        |> Enum.reduce(%{}, fn %{project_id: project_id, count: count}, acc ->
          case Map.get(project_customer_pairs, project_id) do
            nil -> acc
            customer_id -> Map.update(acc, customer_id, count, &(&1 + count))
          end
        end)
        |> Enum.map(fn {customer_id, count} -> {customer_id, count} end)

      {customer_counts, meta}
    end
  end

  def delete_project_events(project_id) do
    ClickHouseRepo.delete_all(from(c in Event, where: c.project_id == ^project_id))
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

  def run_events(project_id, start_date, end_date, opts) do
    query =
      from(e in Event,
        as: :event,
        where:
          e.ran_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.ran_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and
            e.project_id == ^project_id
      )

    query
    |> add_filters(opts)
    |> ClickHouseRepo.all()
    |> Enum.map(&Event.normalize_enums/1)
  end

  def run_average_durations(project_id, start_date, end_date, _date_period, time_bucket, name, opts) do
    date_format = get_date_format(time_bucket)

    query =
      from(e in Event,
        group_by: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
        where:
          e.ran_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.ran_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and e.name == ^name and
            e.project_id == ^project_id,
        select: %{
          date: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
          value: avg(e.duration)
        }
      )

    query
    |> add_filters(Keyword.put(opts, :name, name))
    |> ClickHouseRepo.all()
  end

  def run_count(project_id, start_date, end_date, date_period, _time_bucket, "test", opts) do
    view_name =
      case date_period do
        :month -> "test_runs_analytics_monthly"
        _ -> "test_runs_analytics_daily"
      end

    query =
      from(v in fragment("?", identifier(^view_name)),
        where:
          v.project_id == ^project_id and
            v.date >= ^start_date and
            v.date <= ^end_date,
        select: %{
          date: v.date,
          count: sum(v.run_count)
        },
        group_by: v.date
      )

    query
    |> add_materialized_view_filters(opts)
    |> ClickHouseRepo.all()
  end

  def cache_hit_rate(project_id, start_date, end_date, opts) do
    query =
      from(e in Event,
        as: :event,
        where:
          e.project_id == ^project_id and
            e.ran_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.ran_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]),
        select: %{
          cacheable_targets_count: sum(e.cacheable_targets_count),
          local_cache_target_hits_count: sum(e.local_cache_hits_count),
          remote_cache_target_hits_count: sum(e.remote_cache_hits_count)
        }
      )

    result =
      query
      |> add_filters(opts)
      |> ClickHouseRepo.one()

    result
  end

  def cache_hit_rates(project_id, start_date, end_date, _date_period, time_bucket, opts) do
    date_format = get_date_format(time_bucket)

    query =
      from(e in Event,
        as: :event,
        group_by: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
        where:
          e.ran_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.ran_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and
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

  def selective_testing_hit_rate(project_id, start_date, end_date, opts) do
    query =
      from(e in Event,
        as: :event,
        where:
          e.project_id == ^project_id and
            e.ran_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.ran_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]),
        select: %{
          test_targets_count: sum(e.test_targets_count),
          local_test_target_hits_count: sum(e.local_test_hits_count),
          remote_test_target_hits_count: sum(e.remote_test_hits_count)
        }
      )

    result =
      query
      |> add_filters(opts)
      |> ClickHouseRepo.one()

    result
  end

  def selective_testing_hit_rates(project_id, start_date, end_date, _date_period, time_bucket, opts) do
    date_format = get_date_format(time_bucket)

    query =
      from(e in Event,
        as: :event,
        group_by: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
        where:
          e.ran_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.ran_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and
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

  def count_events_in_period(start_date, end_date) do
    ClickHouseRepo.aggregate(
      from(e in Event,
        where: e.ran_at >= ^start_date and e.ran_at <= ^end_date
      ),
      :count
    )
  end

  def count_all_events do
    ClickHouseRepo.aggregate(from(e in Event, []), :count)
  end

  def run_average_duration(project_id, start_date, end_date, opts) do
    query = build_analytics_query(project_id, start_date, end_date, opts)

    result =
      query
      |> select([event: e], fragment("avg(?)", e.duration))
      |> ClickHouseRepo.one()

    case result do
      nil -> 0
      duration -> duration
    end
  end

  def run_analytics(project_id, start_date, end_date, opts) do
    query = build_analytics_query(project_id, start_date, end_date, opts)

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

  defp build_analytics_query(project_id, start_date, end_date, opts) do
    from(e in Event, as: :event)
    |> where([event: e], e.ran_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]))
    |> where([event: e], e.ran_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]))
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

  defp add_materialized_view_filters(query, opts) do
    query =
      case Keyword.get(opts, :is_ci) do
        nil -> query
        is_ci -> where(query, [v], v.is_ci == ^is_ci)
      end

    case Keyword.get(opts, :status) do
      nil -> query
      :success -> where(query, [v], v.status == 0)
      :failure -> where(query, [v], v.status == 1)
      _ -> query
    end
  end

  def run_count_with_date_range(project_id, start_date, end_date, date_period, time_bucket, name, opts) do
    date_format = get_date_format(time_bucket)

    date_range_query =
      build_clickhouse_date_range_query(start_date, end_date, date_period, date_format)

    data_query =
      add_filters(
        from(e in Event,
          as: :event,
          group_by: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
          where:
            e.ran_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
              e.ran_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and
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

  def run_average_durations_with_date_range(project_id, start_date, end_date, date_period, time_bucket, name, opts) do
    date_format = get_date_format(time_bucket)

    date_range_query =
      build_clickhouse_date_range_query(start_date, end_date, date_period, date_format)

    data_query =
      add_filters(
        from(e in Event,
          as: :event,
          group_by: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
          where:
            e.ran_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
              e.ran_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and e.name == ^name and
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

  defp build_clickhouse_date_range_query(start_date, end_date, date_period, date_format) do
    case date_period do
      :day ->
        from(
          d in fragment(
            """
              SELECT formatDateTime(
                toDateTime(?) + INTERVAL number DAY, 
                ?
              ) AS date
              FROM numbers(dateDiff('day', toDate(?), toDate(?)) + 1)
            """,
            ^NaiveDateTime.new!(start_date, ~T[00:00:00]),
            ^date_format,
            ^start_date,
            ^end_date
          ),
          select: %{date: d.date}
        )

      :month ->
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
end
