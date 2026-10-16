defmodule AtlasWeb.TimeOffLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: [input: 1]

  import AtlasWeb.TimeOffComponents,
    only: [overview: 1, request_modal: 1, request_status: 1, approval_actions: 1, own_actions: 1]

  alias Atlas.TimeOff
  alias Atlas.Users

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, 30_000)

    {:ok,
     socket
     |> assign(:page_title, gettext("Time off"))
     |> assign(:admin?, Users.admin?(socket.assigns.current_user))
     |> assign(:approver?, TimeOff.can_approve?(socket.assigns.current_user))
     |> assign(:editing_request, nil)
     |> assign(:request_form_version, 0)
     |> assign(:booking_form, to_form(TimeOff.change_booking(), as: :booking))
     |> assign(:default_location, TimeOff.default_location())
     |> assign(:holiday_form, to_form(TimeOff.change_holiday(), as: :holiday))
     |> assign(:import_form, to_form(%{"year" => Date.utc_today().year}, as: :import))}
  end

  def handle_params(params, _uri, socket) do
    if socket.assigns.live_action == :settings and !socket.assigns.admin? do
      {:noreply, push_navigate(socket, to: ~p"/people/time-off")}
    else
      month = parse_month(params["month"])
      location_id = ""

      {:noreply,
       socket
       |> assign(:month, month)
       |> assign(:calendar?, params["view"] == "calendar")
       |> assign(
         :query_params,
         params
         |> Map.filter(fn {_key, value} -> is_binary(value) end)
         |> Map.take(["view", "month", "upcoming_page", "requests_page", "holidays_page"])
       )
       |> assign(:location_id, location_id)
       |> assign(
         :filter_form,
         to_form(%{"month" => Calendar.strftime(month, "%Y-%m"), "location" => location_id}, as: :filter)
       )
       |> load_calendar()}
    end
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, 30_000)
    {:noreply, load_calendar(socket)}
  end

  def handle_event("filter", %{"filter" => params}, socket) do
    path = if socket.assigns.live_action == :settings, do: "/people/time-off/settings", else: "/people/time-off"

    params =
      socket.assigns.query_params
      |> Map.merge(Map.take(params, ["month"]))
      |> Map.drop(["upcoming_page", "requests_page", "holidays_page"])

    {:noreply, push_patch(socket, to: path <> "?" <> URI.encode_query(params))}
  end

  def handle_event("new_request", _params, socket) do
    {:noreply, socket |> reset_request() |> push_event("open-modal", %{id: "holiday-request-modal"})}
  end

  def handle_event("edit_request", %{"id" => id}, socket) do
    case TimeOff.get_my_request(id, socket.assigns.current_user) do
      %{status: status} = booking when status != "cancelled" ->
        {:noreply,
         socket
         |> update(:request_form_version, &(&1 + 1))
         |> assign(:editing_request, booking)
         |> assign(:booking_form, to_form(TimeOff.change_booking(booking, %{}), as: :booking))
         |> push_event("open-modal", %{id: "holiday-request-modal"})}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("This holiday request cannot be changed."))}
    end
  end

  def handle_event("close_request_modal", _params, socket) do
    {:noreply, socket |> reset_request() |> push_event("close-modal", %{id: "holiday-request-modal"})}
  end

  def handle_event("holiday_dates_changed", %{"value" => %{"start" => first, "end" => last}}, socket) do
    attrs = %{"starts_on" => first, "ends_on" => last}

    changeset =
      case socket.assigns.editing_request do
        nil -> TimeOff.change_booking(attrs)
        booking -> TimeOff.change_booking(booking, attrs)
      end

    {:noreply, assign(socket, :booking_form, to_form(%{changeset | action: :validate}, as: :booking))}
  end

  def handle_event("report", %{"booking" => attrs}, socket) do
    result =
      case socket.assigns.editing_request do
        nil -> TimeOff.report_holiday(attrs, socket.assigns.current_user)
        booking -> TimeOff.update_holiday(booking.id, attrs, socket.assigns.current_user)
      end

    case result do
      {:ok, _booking} ->
        {:noreply,
         socket
         |> reset_request()
         |> load_calendar()
         |> push_event("close-modal", %{id: "holiday-request-modal"})
         |> put_flash(:info, gettext("Holiday request saved."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :booking_form, to_form(changeset, as: :booking))}

      {:error, :location_required} ->
        {:noreply, put_flash(socket, :error, gettext("Ask an administrator to assign your location calendar first."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("This holiday request cannot be changed."))}
    end
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    case TimeOff.cancel_holiday(id, socket.assigns.current_user) do
      {:ok, _booking} -> {:noreply, socket |> load_calendar() |> put_flash(:info, gettext("Holiday cancelled."))}
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not cancel this holiday."))}
    end
  end

  def handle_event("review", %{"id" => id, "decision" => decision}, socket) do
    case TimeOff.review_holiday(id, decision, socket.assigns.current_user) do
      {:ok, _booking} ->
        {:noreply, socket |> load_calendar() |> put_flash(:info, gettext("Holiday request reviewed."))}

      {:error, :cannot_review_own_request} ->
        {:noreply, put_flash(socket, :error, gettext("Another approver must review your own holiday request."))}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext(
             "Could not review this request. It may already have been reviewed or cancelled, or your permission may have changed."
           )
         )}
    end
  end

  def handle_event("add_holiday", %{"holiday" => attrs}, socket) do
    case TimeOff.add_holiday(socket.assigns.default_location.id, attrs, socket.assigns.current_user) do
      {:ok, _holiday} ->
        {:noreply,
         socket
         |> assign(:holiday_form, to_form(TimeOff.change_holiday(), as: :holiday))
         |> load_calendar()
         |> put_flash(:info, gettext("Local holiday added."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :holiday_form, to_form(changeset, as: :holiday))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not add holiday."))}
    end
  end

  def handle_event("remove_holiday", %{"id" => id}, socket) do
    finish_settings(socket, TimeOff.remove_holiday(id, socket.assigns.current_user), gettext("Public holiday removed."))
  end

  def handle_event("import_holidays", %{"import" => attrs}, socket) do
    year =
      case Integer.parse(attrs["year"] || "") do
        {year, ""} -> year
        _ -> nil
      end

    result = TimeOff.import_holidays(socket.assigns.default_location.id, year, socket.assigns.current_user)

    finish_settings(
      socket,
      result,
      gettext("Public holidays imported. Review regional coverage and add any municipal holidays.")
    )
  end

  def render(assigns) do
    ~H"""
    <section id="time-off-page" data-part="time-off-page">
      <header data-part="header">
        <div>
          <h1>{gettext("Time off")}</h1>
          <p>
            {gettext("Plan holidays and see who is away. Public holidays follow the Berlin calendar.")}
          </p>
        </div>
        <div data-part="header-actions">
          <.link
            :if={@live_action != :settings && @calendar?}
            patch={~p"/people/time-off"}
            id="time-off-list-link"
          >
            {gettext("View upcoming holidays")}
          </.link>
          <.link :if={@live_action == :settings} navigate={~p"/people/time-off"}>
            {gettext("Back to time off")}
          </.link>
          <.request_modal
            :if={@live_action != :settings}
            form={@booking_form}
            editing={@editing_request}
            version={@request_form_version}
          />
        </div>
      </header>
      <AtlasWeb.Layouts.flash_group :if={@flash != %{}} flash={@flash} id="time-off-flashes" />

      <.form
        :if={@calendar? || @live_action == :settings}
        for={@filter_form}
        id="time-off-filter"
        phx-change="filter"
        data-part="filters"
      >
        <.input
          :if={@calendar? || @live_action == :settings}
          field={@filter_form[:month]}
          data-part="time-off-input"
          type="month"
          label={gettext("Month")}
          min="2000-01"
          max="2100-12"
        />
      </.form>

      <%= if @live_action == :settings do %>
        <div id="time-off-settings" data-part="settings">
          <.card title={gettext("Import public holidays")} icon="calendar_week">
            <.card_section>
              <p>
                {gettext(
                  "Import a year from Nager.Date. Reimporting replaces that year's imported dates and preserves manually added holidays. Regional and municipal coverage varies; review the dates before relying on them."
                )}
              </p>
              <.form
                for={@import_form}
                id="time-off-import-form"
                phx-submit="import_holidays"
                data-part="form"
              >
                <.input
                  field={@import_form[:year]}
                  data-part="time-off-input"
                  type="number"
                  min="2000"
                  max="2100"
                  label={gettext("Year")}
                  required
                />
                <.button
                  type="submit"
                  phx-disable-with={gettext("Importing…")}
                  label={gettext("Import public holidays")}
                />
              </.form>
            </.card_section>
          </.card>
          <.card title={gettext("Add a local public holiday")} icon="calendar_week">
            <.card_section>
              <.form
                for={@holiday_form}
                id="time-off-public-holiday-form"
                phx-submit="add_holiday"
                data-part="form"
              >
                <.input
                  field={@holiday_form[:name]}
                  data-part="time-off-input"
                  label={gettext("Holiday name")}
                  required
                />
                <.input
                  field={@holiday_form[:date]}
                  data-part="time-off-input"
                  type="date"
                  label={gettext("Date")}
                  required
                />
                <.button type="submit" label={gettext("Add public holiday")} />
              </.form>
            </.card_section>
          </.card>
        </div>
        <.card title={gettext("Public holidays in the selected year")} icon="calendar_week">
          <.card_section>
            <div id="time-off-public-holidays" phx-update="stream">
              <div :for={{id, holiday} <- @streams.public_holidays} id={id} data-part="list-row">
                <span>
                  {holiday.date} · {holiday.name} · {holiday.location.name} · {holiday.source}
                </span>
                <.button
                  id={"remove-public-holiday-#{holiday.id}"}
                  type="button"
                  variant="secondary"
                  label={gettext("Remove")}
                  phx-click="remove_holiday"
                  phx-value-id={holiday.id}
                  data-confirm={
                    gettext("Remove this public holiday? Leave-day counts will be recalculated.")
                  }
                />
              </div>
            </div>
          </.card_section>
        </.card>
      <% else %>
        <%= if @calendar? do %>
          <.card title={Calendar.strftime(@month, "%B %Y")} icon="calendar_week">
            <.card_section>
              <nav data-part="month-navigation" aria-label={gettext("Calendar navigation")}>
                <.link
                  id="time-off-previous"
                  patch={
                    ~p"/people/time-off?#{%{view: "calendar", month: adjacent_month(@month, -1)}}"
                  }
                >
                  {gettext("Previous month")}
                </.link>
                <span>
                  {gettext(
                    "Approved holiday = confirmed leave · Pending holiday = awaiting approval · Public holiday = location calendar"
                  )}
                </span>
                <.link
                  id="time-off-next"
                  patch={
                    ~p"/people/time-off?#{%{view: "calendar", month: adjacent_month(@month, 1)}}"
                  }
                >
                  {gettext("Next month")}
                </.link>
              </nav>
              <p :if={@missing_coverage?} id="time-off-coverage-warning" role="status">
                {gettext(
                  "Some location calendars have not imported public holidays for this year. Day counts only exclude configured dates and may be incomplete."
                )}
              </p>
              <div data-part="calendar-scroll">
                <div data-part="weekdays" aria-hidden="true">
                  <span :for={
                    day <- [
                      gettext("Mon"),
                      gettext("Tue"),
                      gettext("Wed"),
                      gettext("Thu"),
                      gettext("Fri"),
                      gettext("Sat"),
                      gettext("Sun")
                    ]
                  }>
                    {day}
                  </span>
                </div>
                <div id="time-off-calendar" data-part="team-calendar-grid" phx-update="stream">
                  <div
                    :for={{id, day} <- @streams.days}
                    id={id}
                    data-part="calendar-day"
                    data-outside={day.date.month != @month.month}
                    data-weekend={Date.day_of_week(day.date) > 5}
                  >
                    <time datetime={Date.to_iso8601(day.date)}>{day.date.day}</time>
                    <div :for={entry <- day.entries} data-part="calendar-entry" data-kind={entry.kind}>
                      <strong>{entry.name}</strong>
                      <span>{entry.label}</span>
                    </div>
                  </div>
                </div>
              </div>
            </.card_section>
          </.card>

          <.card title={gettext("Holiday requests overlapping this month")} icon="calendar_week">
            <.card_section>
              <p :if={@bookings_empty?} id="time-off-empty">
                {gettext("No holiday requests for this month.")}
              </p>
              <div id="time-off-bookings" phx-update="stream">
                <div
                  :for={{id, booking} <- @streams.bookings}
                  id={id}
                  data-part="list-row"
                  data-status={booking.status}
                >
                  <div>
                    <strong>{booking.name}</strong>
                    <.request_status booking={booking} prefix="holiday" />
                    <p>
                      {booking.starts_on} – {booking.ends_on} · {booking.working_days} {gettext(
                        "working days"
                      )}
                    </p>
                    <span :if={booking.missing_years != []}>
                      {gettext("Public holiday calendar incomplete")}
                    </span>
                  </div>
                  <.own_actions :if={booking.user_id == @current_user.id} booking={booking} />
                  <.approval_actions
                    booking={booking}
                    allowed={@approver? && booking.user_id != @current_user.id}
                  />
                </div>
              </div>
            </.card_section>
          </.card>
        <% else %>
          <.overview
            streams={@streams}
            upcoming_meta={@upcoming_meta}
            mine_meta={@mine_meta}
            holidays_meta={@holidays_meta}
            current_user={@current_user}
            approver?={@approver?}
            query_params={@query_params}
          />
        <% end %>
      <% end %>
    </section>
    """
  end

  defp load_calendar(socket) do
    if socket.assigns.calendar? or socket.assigns.live_action == :settings,
      do: load_month(socket),
      else: load_overview(socket)
  end

  defp reset_request(socket) do
    socket
    |> assign(:editing_request, nil)
    |> update(:request_form_version, &(&1 + 1))
    |> assign(:booking_form, to_form(TimeOff.change_booking(), as: :booking))
  end

  defp load_overview(socket) do
    data =
      TimeOff.overview(socket.assigns.current_user,
        public_holiday_location_id: socket.assigns.default_location.id,
        upcoming_page: socket.assigns.query_params["upcoming_page"],
        requests_page: socket.assigns.query_params["requests_page"],
        holidays_page: socket.assigns.query_params["holidays_page"]
      )

    socket
    |> assign(:approver?, TimeOff.can_approve?(socket.assigns.current_user))
    |> assign(:upcoming_meta, data.upcoming_meta)
    |> assign(:mine_meta, data.mine_meta)
    |> assign(:holidays_meta, data.holidays_meta)
    |> stream(:upcoming, data.upcoming, reset: true)
    |> stream(:mine, data.mine, reset: true)
    |> stream(:upcoming_holidays, data.public_holidays, reset: true)
  end

  defp load_month(socket) do
    month = socket.assigns.month
    first = Date.add(month, 1 - Date.day_of_week(month))
    last = Date.add(Date.end_of_month(month), 7 - Date.day_of_week(Date.end_of_month(month)))
    {:ok, data} = TimeOff.calendar(first, last, socket.assigns.current_user)
    location_id = socket.assigns.location_id
    users = Enum.filter(data.users, &(location_id == "" or &1.time_off_location_id == location_id))
    requests = Enum.filter(data.requests, &(location_id == "" or &1.location_id == location_id))

    month_bookings =
      Enum.filter(
        requests,
        &(Date.compare(&1.starts_on, Date.end_of_month(month)) != :gt and Date.compare(&1.ends_on, month) != :lt)
      )

    days =
      Enum.map(Date.range(first, last), fn date ->
        %{
          id: Date.to_iso8601(date),
          date: date,
          entries: day_entries(date, data.users, data.bookings, data.holidays, location_id)
        }
      end)

    public_holidays =
      if socket.assigns.live_action == :settings do
        TimeOff.list_holidays(Date.new!(month.year, 1, 1), Date.new!(month.year, 12, 31))
        |> Enum.filter(&(&1.location_id == socket.assigns.default_location.id))
      else
        []
      end

    socket
    |> assign(:approver?, TimeOff.can_approve?(socket.assigns.current_user))
    |> assign(
      :missing_coverage?,
      missing_coverage?(users, month_bookings, month.year)
    )
    |> assign(:bookings_empty?, month_bookings == [])
    |> stream(:days, days, reset: true)
    |> stream(:bookings, month_bookings, reset: true)
    |> stream(:public_holidays, public_holidays, reset: true)
  end

  defp missing_coverage?(users, bookings, year) do
    Enum.any?(bookings, &(&1.missing_years != [])) or
      Enum.any?(users, &(is_nil(&1.time_off_location) or year not in &1.time_off_location.synced_years))
  end

  defp day_entries(date, users, bookings, holidays, selected_location) do
    leave = Enum.filter(bookings, &(Date.compare(date, &1.starts_on) != :lt and Date.compare(date, &1.ends_on) != :gt))

    vacation_entries =
      leave
      |> Enum.filter(&(selected_location == "" or &1.location_id == selected_location))
      |> Enum.map(&leave_entry/1)

    public_entries =
      Enum.flat_map(users, fn user ->
        # During a booking, use its snapshotted location rather than a newly assigned location.
        booking = Enum.find(leave, &(&1.user_id == user.id))
        location_id = if booking, do: booking.location_id, else: user.time_off_location_id

        applicable =
          Enum.filter(
            holidays,
            &(&1.date == date and &1.location_id == location_id and
                (selected_location == "" or location_id == selected_location))
          )

        if applicable == [] do
          []
        else
          [%{name: user.name || user.email, kind: "public", label: Enum.map_join(applicable, ", ", & &1.name)}]
        end
      end)

    vacation_entries ++ public_entries
  end

  defp leave_entry(booking) do
    %{
      name: booking.name,
      kind: if(booking.status == "pending", do: "pending", else: "vacation"),
      label: status_label(booking.status)
    }
  end

  defp status_label("pending"), do: gettext("Pending holiday")
  defp status_label("approved"), do: gettext("Approved holiday")
  defp status_label("rejected"), do: gettext("Rejected")
  defp status_label("cancelled"), do: gettext("Cancelled")

  defp finish_settings(socket, {:ok, _resource}, message),
    do: {:noreply, socket |> load_calendar() |> put_flash(:info, message)}

  defp finish_settings(socket, _error, _message),
    do:
      {:noreply,
       put_flash(
         socket,
         :error,
         gettext(
           "Could not save calendar settings. Check your permissions, location, year, and public holiday provider coverage."
         )
       )}

  defp parse_month(value) when is_binary(value) do
    case Date.from_iso8601(value <> "-01") do
      {:ok, %Date{year: year} = date} when year in 2000..2100 -> date
      _ -> Date.beginning_of_month(Date.utc_today())
    end
  end

  defp parse_month(_value), do: Date.beginning_of_month(Date.utc_today())

  defp adjacent_month(month, offset) do
    month |> Date.shift(month: offset) |> Calendar.strftime("%Y-%m")
  end
end
