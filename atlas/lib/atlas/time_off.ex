defmodule Atlas.TimeOff do
  @moduledoc "Self-reported holidays and location-specific public holiday calendars."

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Repo
  alias Atlas.TimeOff.Booking
  alias Atlas.TimeOff.Holiday
  alias Atlas.TimeOff.Location
  alias Atlas.TimeOff.PublicHolidays
  alias Atlas.Users
  alias Atlas.Users.User

  def default_location, do: Repo.get_by!(Location, name: "Berlin")

  def list_locations, do: Repo.all(from(location in Location, order_by: location.name))

  def location_for(%User{} = user) do
    Repo.one(
      from(location in Location,
        join: person in User,
        on: person.time_off_location_id == location.id,
        where: person.id == ^user.id
      )
    )
  end

  def change_location(attrs \\ %{}), do: Location.changeset(%Location{}, attrs)
  def change_booking(attrs \\ %{}), do: Booking.changeset(%Booking{}, attrs)
  def change_booking(%Booking{} = booking, attrs), do: Booking.changeset(booking, attrs)
  def change_holiday(attrs \\ %{}), do: Holiday.changeset(%Holiday{}, attrs)

  def create_location(attrs, %User{} = actor, opts \\ []) do
    with :ok <- authorize_admin(actor) do
      %Location{}
      |> Location.changeset(attrs)
      |> Repo.insert()
      |> audit_result("time_off.location_created", actor, opts)
    end
  end

  def assign_location(user_id, location_id, %User{} = actor, opts \\ []) do
    with :ok <- authorize_admin(actor),
         {:ok, user_id} <- cast_id(user_id),
         {:ok, location_id} <- cast_id(location_id),
         %User{} = user <- Repo.get(User, user_id),
         %Location{} <- Repo.get(Location, location_id) do
      user
      |> Ecto.Changeset.change(time_off_location_id: location_id)
      |> Repo.update()
      |> audit_result(
        "time_off.location_assigned",
        actor,
        Keyword.put(opts, :previous_location_id, user.time_off_location_id)
      )
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def add_holiday(location_id, attrs, %User{} = actor, opts \\ []) do
    with :ok <- authorize_admin(actor),
         {:ok, location_id} <- cast_id(location_id) do
      %Holiday{location_id: location_id}
      |> Holiday.changeset(attrs)
      |> Repo.insert()
      |> audit_result("time_off.holiday_added", actor, opts)
    end
  end

  def remove_holiday(id, %User{} = actor, opts \\ []) do
    with :ok <- authorize_admin(actor),
         {:ok, id} <- cast_id(id),
         %Holiday{} = holiday <- Repo.get(Holiday, id) do
      holiday
      |> Repo.delete()
      |> audit_result("time_off.holiday_removed", actor, opts)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def import_holidays(location_id, year, actor, opts \\ [])

  def import_holidays(location_id, year, %User{} = actor, opts) when is_integer(year) and year in 2000..2100 do
    with :ok <- authorize_admin(actor),
         {:ok, location_id} <- cast_id(location_id),
         %Location{} = location <- Repo.get(Location, location_id) do
      sync_location_holidays(location, year, actor, opts)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def import_holidays(_location_id, _year, _actor, _opts), do: {:error, :invalid_year}

  def sync_public_holidays(opts \\ []) do
    actor = opts[:actor]

    with :ok <- if(actor, do: authorize_admin(actor), else: :ok) do
      location = default_location()
      year = Date.utc_today().year
      opts = Keyword.put_new(opts, :interface, "worker")

      Enum.reduce_while([year, year + 1], {:ok, location}, fn year, _acc ->
        case sync_location_holidays(location, year, actor, opts) do
          {:ok, location} -> {:cont, {:ok, location}}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp sync_location_holidays(location, year, actor, opts) do
    location_id = location.id

    case PublicHolidays.fetch(location, year) do
      {:ok, holidays} ->
        Repo.transaction(fn ->
          # Serialize imports so replacement and coverage are committed together. Manual local dates survive.
          location =
            Repo.one!(from(location in Location, where: location.id == ^location_id, lock: "FOR NO KEY UPDATE"))

          Repo.delete_all(
            from(holiday in Holiday,
              where:
                holiday.location_id == ^location_id and holiday.source == "nager" and
                  holiday.date >= ^Date.new!(year, 1, 1) and holiday.date <= ^Date.new!(year, 12, 31)
            )
          )

          now = DateTime.truncate(DateTime.utc_now(), :second)

          entries =
            holidays
            |> Enum.uniq_by(&{&1.date, &1.name})
            |> Enum.map(fn attrs ->
              %Holiday{location_id: location_id, source: "nager"}
              |> Holiday.changeset(attrs)
              |> Ecto.Changeset.apply_action(:insert)
              |> unwrap!()
              |> Map.take([:location_id, :source, :name, :date])
              |> Map.merge(%{id: Atlas.UUIDv7.generate(), inserted_at: now, updated_at: now})
            end)

          Repo.insert_all(Holiday, entries)

          location
          |> Ecto.Changeset.change(synced_years: Enum.sort(Enum.uniq([year | location.synced_years])))
          |> Repo.update()
          |> unwrap!()
        end)
        |> audit_result("time_off.holidays_imported", actor, Keyword.put(opts, :year, year))

      nil ->
        {:error, :not_found}

      error ->
        error
    end
  end

  def report_holiday(attrs, %User{} = actor, opts \\ []) do
    Repo.transaction(fn ->
      # All reporting paths lock the same user, preventing concurrent overlapping bookings.
      user = Repo.one!(from(user in User, where: user.id == ^actor.id, lock: "FOR UPDATE"))
      location_id = user.time_off_location_id || default_location().id
      changeset = Booking.changeset(%Booking{user_id: user.id, location_id: location_id}, attrs)

      changeset |> validate_no_overlap() |> Repo.insert() |> unwrap!()
    end)
    |> audit_result("time_off.reported", actor, opts)
  end

  def get_my_request(id, %User{} = actor) do
    case cast_id(id) do
      {:ok, id} ->
        Repo.one(
          from(booking in Booking, where: booking.id == ^id and booking.user_id == ^actor.id, preload: :location)
        )

      _ ->
        nil
    end
  end

  def update_holiday(id, attrs, %User{} = actor, opts \\ []) do
    with {:ok, id} <- cast_id(id) do
      Repo.transaction(fn ->
        # Use the same lock order as creation so edits cannot race overlapping new requests.
        Repo.one!(from(user in User, where: user.id == ^actor.id, lock: "FOR UPDATE"))

        booking =
          Repo.one(
            from(booking in Booking, where: booking.id == ^id and booking.user_id == ^actor.id, lock: "FOR UPDATE")
          )

        if is_nil(booking), do: Repo.rollback(:not_found)
        if booking.status == "cancelled", do: Repo.rollback(:not_active)
        changeset = booking |> Booking.changeset(attrs) |> validate_no_overlap()

        if changeset.valid? and changeset.changes == %{} and booking.status != "rejected" do
          booking
        else
          previous = Map.take(booking, [:starts_on, :ends_on, :status, :reviewed_by_id, :reviewed_at])

          changeset
          |> Ecto.Changeset.change(status: "pending", reviewed_by_id: nil, reviewed_at: nil)
          |> Repo.update()
          |> audit_result("time_off.updated", actor, Keyword.put(opts, :previous, previous))
          |> unwrap!()
        end
      end)
    end
  end

  defp validate_no_overlap(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp validate_no_overlap(changeset) do
    first = Ecto.Changeset.get_field(changeset, :starts_on)
    last = Ecto.Changeset.get_field(changeset, :ends_on)
    user_id = changeset.data.user_id
    id = changeset.data.id

    query =
      from(booking in Booking,
        where:
          booking.user_id == ^user_id and booking.status in ["pending", "approved"] and booking.starts_on <= ^last and
            booking.ends_on >= ^first
      )

    query = if id, do: where(query, [booking], booking.id != ^id), else: query

    if Repo.exists?(query),
      do: Ecto.Changeset.add_error(changeset, :starts_on, "overlaps an existing holiday"),
      else: changeset
  end

  def cancel_holiday(id, %User{} = actor, opts \\ []) do
    with {:ok, id} <- cast_id(id) do
      Repo.transaction(fn ->
        booking = Repo.one(from(booking in Booking, where: booking.id == ^id, lock: "FOR UPDATE"))
        if is_nil(booking), do: Repo.rollback(:not_found)
        if booking.user_id != actor.id, do: Repo.rollback(:forbidden)
        if booking.status not in ["pending", "approved"], do: Repo.rollback(:not_active)

        booking
        |> Ecto.Changeset.change(status: "cancelled", cancelled_at: DateTime.truncate(DateTime.utc_now(), :second))
        |> Repo.update()
        |> unwrap!()
      end)
      |> audit_result("time_off.cancelled", actor, opts)
    end
  end

  def can_approve?(actor), do: Users.has_scope?(actor, "time_off_approvals:write")

  def review_holiday(id, decision, actor, opts \\ [])

  def review_holiday(id, decision, %User{} = actor, opts) when decision in ["approved", "rejected"] do
    with true <- can_approve?(actor),
         {:ok, id} <- cast_id(id) do
      Repo.transaction(fn ->
        booking = Repo.one(from(booking in Booking, where: booking.id == ^id, lock: "FOR UPDATE"))
        if is_nil(booking), do: Repo.rollback(:not_found)
        if booking.user_id == actor.id, do: Repo.rollback(:cannot_review_own_request)
        if booking.status != "pending", do: Repo.rollback(:not_pending)

        booking
        |> Ecto.Changeset.change(
          status: decision,
          reviewed_by_id: actor.id,
          reviewed_at: DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update()
        |> unwrap!()
      end)
      |> audit_result("time_off." <> decision, actor, opts)
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  def review_holiday(_id, _decision, _actor, _opts), do: {:error, :invalid_decision}

  @doc "A bounded calendar window. Rejected/cancelled history requires ownership or time_off_approvals:read."
  def calendar(%Date{} = first, %Date{} = last, actor \\ nil) do
    if Date.diff(last, first) in 0..61 do
      users = User |> order_by([user], user.name) |> preload(:time_off_location) |> Repo.all()

      requests =
        from(booking in Booking,
          where: booking.starts_on <= ^last and booking.ends_on >= ^first,
          order_by: [booking.starts_on, booking.id],
          preload: [:user, :location]
        )
        |> visible_requests(actor)
        |> Repo.all()

      # Include dates outside the window to calculate the full duration of edge-spanning bookings.
      holiday_first = Enum.reduce(requests, first, &Enum.min([&1.starts_on, &2], Date))
      holiday_last = Enum.reduce(requests, last, &Enum.max([&1.ends_on, &2], Date))
      holidays = list_holidays(holiday_first, holiday_last)
      summaries = Enum.map(requests, &booking_summary(&1, holidays))

      {:ok,
       %{
         users: users,
         bookings: Enum.filter(summaries, &(&1.status in ["pending", "approved"])),
         requests: summaries,
         holidays: holidays,
         locations: list_locations()
       }}
    else
      {:error, :invalid_date_range}
    end
  end

  @doc "Paginated upcoming team leave, the caller's own request history, and upcoming public holidays."
  def overview(%User{} = actor, opts \\ []) do
    first = Keyword.get(opts, :from, Date.utc_today())

    {upcoming, upcoming_meta} =
      from(booking in Booking,
        where: booking.status in ["pending", "approved"] and booking.ends_on >= ^first,
        order_by: [asc: booking.starts_on, asc: booking.id],
        preload: [:user, :location]
      )
      |> filter_location(opts[:location_id])
      |> paginate(opts[:upcoming_page], opts[:page_size])

    {mine, mine_meta} =
      from(booking in Booking,
        where: booking.user_id == ^actor.id,
        order_by: [desc: booking.updated_at, desc: booking.id],
        preload: [:user, :location]
      )
      |> paginate(opts[:requests_page], opts[:page_size])

    {holidays, holidays_meta} =
      from(holiday in Holiday,
        where: holiday.date >= ^first,
        order_by: [asc: holiday.date, asc: holiday.id],
        preload: :location
      )
      |> filter_location(opts[:public_holiday_location_id] || opts[:location_id] || default_location().id)
      |> paginate(opts[:holidays_page], opts[:page_size])

    bookings = Enum.uniq_by(upcoming ++ mine, & &1.id)
    dates = Enum.flat_map(bookings, &[&1.starts_on, &1.ends_on])
    count_holidays = if dates == [], do: [], else: list_holidays(Enum.min(dates, Date), Enum.max(dates, Date))

    %{
      upcoming: Enum.map(upcoming, &booking_summary(&1, count_holidays)),
      upcoming_meta: upcoming_meta,
      mine: Enum.map(mine, &booking_summary(&1, count_holidays)),
      mine_meta: mine_meta,
      public_holidays: holidays,
      holidays_meta: holidays_meta
    }
  end

  defp paginate(query, page, size) do
    size = min(positive_integer(size, 10), 50)
    count = Flop.count(query, %Flop{}, repo: Repo)
    last_page = max(div(count + size - 1, size), 1)
    page = min(positive_integer(page, 1), last_page)
    Flop.run(query, %Flop{page: page, page_size: size}, repo: Repo, count: count)
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> default
    end
  end

  defp positive_integer(_value, default), do: default

  defp filter_location(query, value) when value in [nil, ""], do: query

  defp filter_location(query, value) do
    case cast_id(value) do
      {:ok, id} -> where(query, [row], row.location_id == ^id)
      _ -> where(query, false)
    end
  end

  defp visible_requests(query, %User{} = actor) do
    history? = Users.has_scope?(actor, "time_off_approvals:read")
    where(query, [booking], booking.status in ["pending", "approved"] or booking.user_id == ^actor.id or ^history?)
  end

  defp visible_requests(query, _actor), do: where(query, [booking], booking.status in ["pending", "approved"])

  def list_holidays(first, last) do
    Repo.all(
      from(holiday in Holiday,
        where: holiday.date >= ^first and holiday.date <= ^last,
        order_by: [holiday.date, holiday.name],
        preload: :location
      )
    )
  end

  def working_days(first, last, holidays) do
    holidays = MapSet.new(holidays, & &1.date)
    Enum.count(Date.range(first, last), &(Date.day_of_week(&1) <= 5 and !MapSet.member?(holidays, &1)))
  end

  defp booking_summary(booking, holidays) do
    holidays = Enum.filter(holidays, &(&1.location_id == booking.location_id))

    %{
      id: booking.id,
      user_id: booking.user_id,
      name: booking.user.name || booking.user.email,
      location_id: booking.location_id,
      location: booking.location.name,
      status: booking.status,
      reviewed_by_id: booking.reviewed_by_id,
      reviewed_at: booking.reviewed_at && DateTime.to_iso8601(booking.reviewed_at),
      starts_on: booking.starts_on,
      ends_on: booking.ends_on,
      working_days: working_days(booking.starts_on, booking.ends_on, holidays),
      missing_years: Enum.to_list(booking.starts_on.year..booking.ends_on.year) -- booking.location.synced_years
    }
  end

  defp authorize_admin(actor) do
    if Users.admin?(actor), do: :ok, else: {:error, :forbidden}
  end

  defp cast_id(id) do
    case Atlas.UUIDv7.cast(id) do
      {:ok, id} -> {:ok, id}
      _ -> {:error, :not_found}
    end
  end

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, reason}), do: Repo.rollback(reason)

  defp audit_result({:ok, resource} = result, action, actor, opts) do
    Audit.record(action, %{
      actor_id: actor && actor.id,
      interface: Keyword.get(opts, :interface, "dashboard"),
      target_type: "time_off",
      target_id: resource.id,
      target_label: Map.get(resource, :name) || Map.get(resource, :email),
      metadata: %{
        "path" => "/people/time-off",
        "user_id" => if(match?(%User{}, resource), do: resource.id, else: Map.get(resource, :user_id)),
        "location_id" =>
          if(match?(%Location{}, resource),
            do: resource.id,
            else: Map.get(resource, :location_id) || Map.get(resource, :time_off_location_id)
          ),
        "previous_location_id" => opts[:previous_location_id],
        "starts_on" => Map.get(resource, :starts_on),
        "ends_on" => Map.get(resource, :ends_on),
        "date" => Map.get(resource, :date),
        "source" => Map.get(resource, :source),
        "country_code" => Map.get(resource, :country_code),
        "subdivision_code" => Map.get(resource, :subdivision_code),
        "year" => opts[:year],
        "status" => Map.get(resource, :status),
        "reviewed_by_id" => Map.get(resource, :reviewed_by_id),
        "previous" => opts[:previous]
      }
    })

    result
  end

  defp audit_result(error, _action, _actor, _opts), do: error
end
