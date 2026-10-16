defmodule AtlasWeb.TimeOffLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Atlas.TimeOffFixtures
  import Phoenix.LiveViewTest

  alias Atlas.Authorization.Roles
  alias Atlas.TimeOff
  alias Atlas.TimeOff.PublicHolidays

  setup %{conn: conn} do
    {conn, user} = log_in_user(conn)
    admin = admin_fixture()
    location = TimeOff.default_location()
    first = Date.add(Date.utc_today(), 10)
    attrs = %{starts_on: Date.to_iso8601(first), ends_on: Date.to_iso8601(Date.add(first, 4))}
    %{conn: conn, user: user, admin: admin, location: location, attrs: attrs, first: first}
  end

  test "default page is Berlin-only with no location or calendar-management controls", %{
    conn: conn,
    attrs: attrs,
    user: user
  } do
    {:ok, view, _} = live(conn, ~p"/people/time-off?location=ignored")
    assert has_element?(view, "#time-off-overview")
    refute has_element?(view, "#time-off-filter")
    refute has_element?(view, "#time-off-calendar-link")
    refute has_element?(view, "#time-off-settings-link")
    assert render(view) =~ "automatically synced from Nager.Date"
    view |> element("#request-holiday-button") |> render_click()
    assert_push_event(view, "open-modal", %{id: "holiday-request-modal"})
    assert has_portal_element?(view, "#time-off-booking-form")

    assert has_portal_element?(
             view,
             "[data-part='holiday-range-picker'].noora-date-picker[phx-hook='NooraDatePicker'][data-date-only='true']"
           )

    refute has_portal_element?(view, "#time-off-booking-form input[type='date']")
    refute has_portal_element?(view, "#report-holiday[disabled]")

    render_hook(view, "holiday_dates_changed", %{
      "value" => %{"start" => attrs.starts_on, "end" => attrs.ends_on},
      "preset" => "custom"
    })

    send(view.pid, :refresh)
    assert has_portal_element?(view, "input[name='booking[ends_on]'][value='#{attrs.ends_on}']")
    render_submit(view, "report", %{"booking" => attrs})
    assert_push_event(view, "close-modal", %{id: "holiday-request-modal"})
    [booking] = TimeOff.overview(user).mine
    assert has_element?(view, "#mine-status-#{booking.id}.noora-badge[data-color='warning']", "Pending holiday")
    assert has_element?(view, "#edit-holiday-#{booking.id}.noora-button-dropdown")
    assert has_portal_element?(view, "#cancel-holiday-#{booking.id}[phx-click='cancel']")
    assert TimeOff.get_my_request(booking.id, user).location_id == TimeOff.default_location().id
  end

  test "my requests includes past and rejected requests", %{conn: conn, user: user, admin: admin, first: first} do
    past = Date.add(first, -60)
    {:ok, booking} = TimeOff.report_holiday(%{starts_on: past, ends_on: Date.add(past, 3)}, user)
    {:ok, _} = TimeOff.review_holiday(booking.id, "rejected", admin)
    {:ok, view, _} = live(conn, ~p"/people/time-off")
    assert has_element?(view, "#mine-status-#{booking.id}.noora-badge[data-color='destructive']", "Rejected")
    assert has_element?(view, "#edit-holiday-#{booking.id}-button")
    refute has_portal_element?(view, "#cancel-holiday-#{booking.id}")
    assert has_element?(view, "#time-off-upcoming-empty")
  end

  test "editing approved requests through the dropdown primary action requires fresh approval", %{
    conn: conn,
    user: user,
    admin: admin,
    attrs: attrs,
    first: first
  } do
    {:ok, booking} = TimeOff.report_holiday(attrs, user)
    {:ok, _} = TimeOff.review_holiday(booking.id, "approved", admin)
    {:ok, view, _} = live(conn, ~p"/people/time-off")
    assert has_element?(view, "#mine-status-#{booking.id}.noora-badge[data-color='success']")
    view |> element("#edit-holiday-#{booking.id}-button") |> render_click()
    assert_push_event(view, "open-modal", %{id: "holiday-request-modal"})

    assert has_portal_element?(
             view,
             "#time-off-booking-form input[name='booking[starts_on]'][value='#{attrs.starts_on}']"
           )

    assert has_portal_element?(view, "#holiday-edit-approval-notice")

    assert has_portal_element?(
             view,
             "[data-part='holiday-range-picker'][data-period-start='#{attrs.starts_on}T00:00:00Z'][data-period-end='#{attrs.ends_on}T00:00:00Z']"
           )

    changed = %{starts_on: Date.to_iso8601(Date.add(first, 20)), ends_on: Date.to_iso8601(Date.add(first, 24))}
    render_submit(view, "report", %{"booking" => changed})
    assert_push_event(view, "close-modal", %{id: "holiday-request-modal"})
    assert has_element?(view, "#mine-status-#{booking.id}", "Pending holiday")
    assert TimeOff.get_my_request(booking.id, user).reviewed_by_id == nil
  end

  test "invalid edit drafts survive refresh", %{conn: conn, user: user, attrs: attrs, first: first} do
    {:ok, booking} = TimeOff.report_holiday(attrs, user)
    {:ok, view, _} = live(conn, ~p"/people/time-off")
    view |> element("#edit-holiday-#{booking.id}-button") |> render_click()
    invalid = Map.put(attrs, :ends_on, Date.to_iso8601(Date.add(first, -1)))
    render_submit(view, "report", %{"booking" => invalid})
    send(view.pid, :refresh)
    assert render(view) =~ "must be on or after the start date"

    assert has_portal_element?(
             view,
             "#time-off-booking-form input[name='booking[ends_on]'][value='#{invalid.ends_on}']"
           )

    assert Date.to_iso8601(TimeOff.get_my_request(booking.id, user).ends_on) == attrs.ends_on
  end

  test "requesting after closing an edit starts with a clean form", %{conn: conn, user: user, attrs: attrs} do
    {:ok, booking} = TimeOff.report_holiday(attrs, user)
    {:ok, view, _} = live(conn, ~p"/people/time-off")
    view |> element("#edit-holiday-#{booking.id}-button") |> render_click()
    render_hook(view, "close_request_modal", %{})
    view |> element("#request-holiday-button") |> render_click()
    refute has_portal_element?(view, "#holiday-edit-approval-notice")
    refute has_portal_element?(view, "#time-off-booking-form input[value='#{attrs.starts_on}']")
    refute has_portal_element?(view, "[data-part='holiday-range-picker'][data-period-start]")
  end

  test "calendar selection supports single days and shows invalid range errors", %{conn: conn, user: user, first: first} do
    {:ok, view, _} = live(conn, ~p"/people/time-off")
    view |> element("#request-holiday-button") |> render_click()

    render_hook(view, "holiday_dates_changed", %{
      "value" => %{"start" => Date.to_iso8601(first), "end" => Date.to_iso8601(Date.add(first, 366))}
    })

    assert render(view) =~ "must be within one year of the start date"
    assert TimeOff.overview(user).mine == []
    attrs = %{starts_on: Date.to_iso8601(first), ends_on: Date.to_iso8601(first)}
    render_hook(view, "holiday_dates_changed", %{"value" => %{"start" => attrs.starts_on, "end" => attrs.ends_on}})
    refute render(view) =~ "must be within one year of the start date"
    render_submit(view, "report", %{"booking" => attrs})
    [booking] = TimeOff.overview(user).mine
    assert booking.starts_on == first
    assert booking.ends_on == first
  end

  test "malformed or incomplete calendar dates stay as validation errors", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, ~p"/people/time-off")
    view |> element("#request-holiday-button") |> render_click()
    render_hook(view, "holiday_dates_changed", %{"value" => %{"start" => "not-a-date", "end" => ""}})
    assert render(view) =~ "is invalid"
    assert TimeOff.overview(user).mine == []
    refute has_portal_element?(view, "[data-part='holiday-range-picker'][data-period-start]")
  end

  test "cancellation from the menu keeps history and removes upcoming leave", %{conn: conn, user: user, attrs: attrs} do
    {:ok, booking} = TimeOff.report_holiday(attrs, user)
    {:ok, view, _} = live(conn, ~p"/people/time-off")
    assert has_portal_element?(view, "#cancel-holiday-#{booking.id}[data-confirm]")
    render_hook(view, "cancel", %{"id" => booking.id})
    assert has_element?(view, "#mine-status-#{booking.id}.noora-badge[data-color='neutral']", "Cancelled")
    assert has_element?(view, "#time-off-upcoming-empty")
    refute has_element?(view, "#edit-holiday-#{booking.id}")
    refute has_portal_element?(view, "#cancel-holiday-#{booking.id}")
  end

  test "members cannot see approval menus or forge approval, edit, or cancellation events", %{conn: conn, attrs: attrs} do
    teammate = user_fixture()
    {:ok, booking} = TimeOff.report_holiday(attrs, teammate)
    {:ok, view, _} = live(conn, ~p"/people/time-off")
    refute has_element?(view, "#approve-holiday-#{booking.id}")
    refute has_portal_element?(view, "#reject-holiday-#{booking.id}")
    refute has_element?(view, "#edit-holiday-#{booking.id}")
    render_hook(view, "edit_request", %{"id" => booking.id})
    render_hook(view, "cancel", %{"id" => booking.id})
    render_hook(view, "review", %{"id" => booking.id, "decision" => "approved"})
    assert has_element?(view, "#upcoming-status-#{booking.id}", "Pending holiday")
    assert {:error, {:live_redirect, %{to: "/people/time-off"}}} = live(conn, ~p"/people/time-off/settings")
  end

  test "read-only approval scopes and administrator access alone do not reveal approval actions", %{attrs: attrs} do
    {:ok, booking} = TimeOff.report_holiday(attrs, user_fixture())

    for scopes <- [["time_off_approvals:read"], ["admin:write"]] do
      {conn, _} = log_in_user(build_conn(), %{scopes: scopes})
      {:ok, view, _} = live(conn, ~p"/people/time-off")
      refute has_element?(view, "#approve-holiday-#{booking.id}")
      refute has_portal_element?(view, "#reject-holiday-#{booking.id}")
      render_hook(view, "review", %{"id" => booking.id, "decision" => "approved"})
      assert has_element?(view, "#upcoming-status-#{booking.id}", "Pending holiday")
    end
  end

  test "delegated approval scope exposes the Noora dropdown and permits approval", %{attrs: attrs} do
    {conn, _} = log_in_user(build_conn(), %{scopes: ["time_off_approvals:write"]})
    {:ok, booking} = TimeOff.report_holiday(attrs, user_fixture())
    {:ok, view, _} = live(conn, ~p"/people/time-off")
    assert has_element?(view, "#approve-holiday-#{booking.id}.noora-button-dropdown")
    assert has_portal_element?(view, "#reject-holiday-#{booking.id}[phx-value-decision='rejected']")
    view |> element("#approve-holiday-#{booking.id}-button") |> render_click()
    assert has_element?(view, "#upcoming-status-#{booking.id}", "Approved holiday")
    refute has_element?(view, "#approve-holiday-#{booking.id}")
    refute has_portal_element?(view, "#reject-holiday-#{booking.id}")
  end

  test "approvers cannot review their own requests", %{attrs: attrs} do
    {conn, user} = log_in_user(build_conn(), %{scopes: ["time_off_approvals:write"]})
    {:ok, booking} = TimeOff.report_holiday(attrs, user)
    {:ok, view, _} = live(conn, ~p"/people/time-off")
    refute has_element?(view, "#approve-holiday-#{booking.id}")
    refute has_portal_element?(view, "#reject-holiday-#{booking.id}")
    render_hook(view, "review", %{"id" => booking.id, "decision" => "approved"})
    assert has_element?(view, "#mine-status-#{booking.id}", "Pending holiday")
  end

  test "revoked approval permission is enforced immediately and menus disappear on refresh", %{attrs: attrs} do
    {conn, reviewer} = log_in_user(build_conn(), %{scopes: ["time_off_approvals:write"]})
    {:ok, booking} = TimeOff.report_holiday(attrs, user_fixture())
    {:ok, view, _} = live(conn, ~p"/people/time-off")
    assert has_element?(view, "#approve-holiday-#{booking.id}")
    {:ok, _} = Roles.set_user_roles(reviewer, [])
    render_hook(view, "review", %{"id" => booking.id, "decision" => "approved"})
    assert has_element?(view, "#upcoming-status-#{booking.id}", "Pending holiday")
    send(view.pid, :refresh)
    refute has_element?(view, "#approve-holiday-#{booking.id}")
    refute has_portal_element?(view, "#reject-holiday-#{booking.id}")
  end

  test "monthly team grid and request picker use separate layout parts", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/people/time-off?view=calendar")

    assert has_element?(view, "[data-part='calendar-scroll'] > #time-off-calendar[data-part='team-calendar-grid']")
    refute has_element?(view, "[data-part='calendar-scroll'] > [data-part='calendar']")

    assert has_portal_element?(
             view,
             "[data-part='holiday-range-picker'] > [data-part='positioner'] > [data-part='content'] > [data-part='calendar'] > [data-part='months']"
           )

    assert has_portal_element?(view, "[data-part='holiday-range-picker'] [data-part='calendar'] > [data-part='footer']")
    refute has_portal_element?(view, "[data-part='holiday-range-picker'] [data-part='team-calendar-grid']")
    refute has_portal_element?(view, "[data-part='calendar-scroll'] [data-part='holiday-range-picker']")
  end

  test "calendar compatibility view retains Noora actions without location filters", %{conn: conn, user: user} do
    {:ok, _} = TimeOff.report_holiday(%{starts_on: "2026-05-01", ends_on: "2026-05-05"}, user)
    {:ok, view, _} = live(conn, ~p"/people/time-off?view=calendar&month=2026-05")
    assert has_element?(view, "#time-off-calendar [data-kind='pending']", user.name)
    refute has_element?(view, "#filter_location")
    view |> form("#time-off-filter", filter: %{month: "2026-05"}) |> render_change()
    view |> element("#time-off-next") |> render_click()
    assert has_element?(view, "#time-off-empty")
  end

  test "legacy settings configure Berlin without asking for a location", %{location: location, first: first} do
    {conn, admin} = log_in_user(build_conn(), %{scopes: ["admin:write"]})
    {:ok, _} = TimeOff.add_holiday(location.id, %{name: "Local day", date: first}, admin)
    {:ok, view, _} = live(conn, ~p"/people/time-off")
    assert has_element?(view, "#time-off-upcoming-public-holidays", "Local day")
    {:ok, view, _} = live(conn, ~p"/people/time-off/settings?month=2026-05")
    refute has_element?(view, "#time-off-location-form")
    refute has_element?(view, "select")

    expect(PublicHolidays, :fetch, fn provider_location, 2026 ->
      assert provider_location.subdivision_code == "DE-BE"
      {:ok, [%{name: "May Day", date: ~D[2026-05-01]}]}
    end)

    view |> form("#time-off-import-form", import: %{year: "2026"}) |> render_submit()
    assert has_element?(view, "#time-off-public-holidays", "May Day")
  end

  test "the three lists paginate independently", %{
    conn: conn,
    user: user,
    admin: admin,
    location: location,
    first: first
  } do
    bookings =
      for index <- 0..10 do
        day = Date.add(first, index * 3)
        {:ok, booking} = TimeOff.report_holiday(%{starts_on: day, ends_on: day}, user)
        {:ok, _} = TimeOff.add_holiday(location.id, %{name: "Public day #{index}", date: day}, admin)
        booking
      end

    earliest = hd(bookings)
    latest = List.last(bookings)
    {:ok, view, _} = live(conn, ~p"/people/time-off")
    assert has_element?(view, "#upcoming-status-#{earliest.id}")
    refute has_element?(view, "#upcoming-status-#{latest.id}")
    view |> element("#time-off-upcoming-pagination [data-part='page-button']", "2") |> render_click()
    assert has_element?(view, "#upcoming-status-#{latest.id}")
    view |> element("#time-off-my-pagination [data-part='page-button']", "2") |> render_click()
    assert has_element?(view, "#mine-status-#{earliest.id}")
    refute has_element?(view, "#mine-status-#{latest.id}")
    view |> element("#time-off-holidays-pagination [data-part='page-button']", "2") |> render_click()
    assert has_element?(view, "#time-off-upcoming-public-holidays", "Public day 10")
  end

  # LiveViewTest does not mount Noora's modal and dropdown portals.
  defp has_portal_element?(view, selector) do
    view
    |> render()
    |> String.replace("<template", "<div")
    |> String.replace("</template>", "</div>")
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.any?()
  end
end
