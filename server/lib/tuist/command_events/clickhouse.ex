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

    project_to_customer =
      from(a in Account, where: not is_nil(a.customer_id), select: {a.id, a.customer_id})
      |> Repo.all()
      |> Map.new()
      |> then(fn account_lookup ->
        from(p in Project,
          where: p.account_id in ^Map.keys(account_lookup),
          select: {p.id, p.account_id}
        )
        |> Repo.all()
        |> Enum.map(fn {project_id, account_id} ->
          {project_id, Map.get(account_lookup, account_id)}
        end)
        |> Enum.filter(fn {_, customer_id} -> customer_id end)
        |> Map.new()
      end)

    query =
      from(e in Event,
        where:
          e.ran_at >= ^start_of_yesterday and e.ran_at <= ^end_of_yesterday and
            e.project_id in ^Map.keys(project_to_customer),
        group_by: e.project_id,
        select: %{
          project_id: e.project_id,
          count:
            count(
              fragment(
                "CASE WHEN COALESCE(length(?), 0) > 0 OR COALESCE(length(?), 0) > 0 THEN 1 ELSE NULL END",
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
        customer_id = Map.get(project_to_customer, project_id)
        Map.update(acc, customer_id, count, &(&1 + count))
      end)
      |> Enum.map(fn {customer_id, count} -> {customer_id, count} end)

    {customer_counts, meta}
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

  def runs_analytics(project_id, start_date, end_date, opts) do
    query =
      from(e in Event,
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

  def runs_analytics_average_durations(project_id, start_date, end_date, _date_period, time_bucket, name, opts) do
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

  def runs_analytics_count(project_id, start_date, end_date, _date_period, time_bucket, name, opts) do
    date_format = get_date_format(time_bucket)

    query =
      from(e in Event,
        group_by: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
        where:
          e.ran_at > ^NaiveDateTime.new!(start_date, ~T[00:00:00]) and
            e.ran_at < ^NaiveDateTime.new!(end_date, ~T[23:59:59]) and
            e.project_id == ^project_id,
        select: %{
          date: fragment("formatDateTime(?, ?)", e.ran_at, ^date_format),
          count: count(e.id)
        }
      )

    query
    |> add_filters(Keyword.put(opts, :name, name))
    |> ClickHouseRepo.all()
  end

  def cache_hit_rate(project_id, start_date, end_date, opts) do
    query =
      from(e in Event,
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

  defp add_filters(query, opts) do
    query = query_with_is_ci_filter(query, opts)

    scheme = Keyword.get(opts, :scheme)

    query =
      case scheme do
        nil -> query
        _ -> where(query, [e], e.scheme == ^scheme)
      end

    category = Keyword.get(opts, :category)

    query =
      case category do
        nil -> query
        _ -> where(query, [e], e.category == ^category)
      end

    status = Keyword.get(opts, :status)

    query =
      case status do
        nil -> query
        :success -> where(query, [e], e.status == 0)
        :failure -> where(query, [e], e.status == 1)
        _ -> query
      end

    add_name_filter(query, opts)
  end

  defp query_with_is_ci_filter(query, opts) do
    is_ci = Keyword.get(opts, :is_ci)

    case is_ci do
      nil -> query
      true -> where(query, [e], e.is_ci == true)
      false -> where(query, [e], e.is_ci == false)
    end
  end

  defp add_name_filter(query, opts) do
    name = Keyword.get(opts, :name)

    case name do
      "test" ->
        where(
          query,
          [e],
          (e.name == "xcodebuild" and
             (e.subcommand == "test" or e.subcommand == "test-without-building")) or
            e.name == "test"
        )

      _ ->
        query
    end
  end

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
end
