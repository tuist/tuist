defmodule Atlas.TimeOffTest do
  use Atlas.DataCase, async: true
  use Mimic

  import Atlas.TimeOffFixtures

  alias Atlas.Audit.Activity
  alias Atlas.Authorization.Roles
  alias Atlas.Repo
  alias Atlas.TimeOff
  alias Atlas.TimeOff.Booking
  alias Atlas.TimeOff.PublicHolidays

  setup do
    admin = admin_fixture()
    location = location_fixture(admin)
    user = assign_fixture(user_fixture(), location, admin)
    %{admin: admin, location: location, user: user}
  end

  test "validates location codes and normalizes ISO identifiers", %{admin: admin} do
    assert {:ok, location} =
             TimeOff.create_location(
               %{
                 name: "Normalized #{System.unique_integer([:positive])}",
                 country_code: "de",
                 subdivision_code: "de-be"
               },
               admin
             )

    assert location.country_code == "DE"
    assert location.subdivision_code == "DE-BE"

    assert {:error, changeset} =
             TimeOff.create_location(%{name: "Invalid", country_code: "DE", subdivision_code: "US-NY"}, admin)

    assert "must belong to the selected country" in errors_on(changeset).subdivision_code
    assert {:error, %Ecto.Changeset{}} = TimeOff.create_location(%{name: "Invalid", country_code: "../DE"}, admin)
  end

  test "defaults to Berlin and never trusts ownership or status in submitted attributes", %{
    user: user,
    location: location
  } do
    unassigned = user_fixture()
    assert {:ok, default_booking} = TimeOff.report_holiday(dates(), unassigned)
    assert default_booking.location_id == TimeOff.default_location().id

    {:ok, booking} =
      TimeOff.report_holiday(
        Map.merge(dates(), %{user_id: unassigned.id, location_id: "ignored", status: "cancelled"}),
        user
      )

    assert booking.user_id == user.id
    assert booking.location_id == location.id
    assert booking.status == "pending"
    assert booking.reviewed_by_id == nil
  end

  test "approval requires a dedicated permission, rejects self-review, and records the decision", %{
    admin: admin,
    user: user
  } do
    {:ok, booking} = TimeOff.report_holiday(dates(), user)
    assert {:error, :forbidden} = TimeOff.review_holiday(booking.id, "approved", user)
    assert {:ok, approved} = TimeOff.review_holiday(booking.id, "approved", admin, interface: "mcp")
    assert approved.status == "approved"
    assert approved.reviewed_by_id == admin.id
    assert approved.reviewed_at
    assert {:error, :not_pending} = TimeOff.review_holiday(booking.id, "rejected", admin)
    assert {:error, :invalid_decision} = TimeOff.review_holiday(booking.id, "unknown", admin)
    event = Repo.get_by!(Activity, action: "time_off.approved", target_id: booking.id)
    assert event.actor_id == admin.id
    assert event.interface == "mcp"
    assert event.metadata["status"] == "approved"
    assert event.metadata["reviewed_by_id"] == admin.id

    {:ok, _} = TimeOff.assign_location(admin.id, booking.location_id, admin)
    {:ok, own} = TimeOff.report_holiday(dates(), admin)
    assert {:error, :cannot_review_own_request} = TimeOff.review_holiday(own.id, "approved", admin)
  end

  test "a delegated approver needs no executive title or administrator scope", %{admin: admin, user: user} do
    approver = user_fixture()
    AtlasWeb.ConnCase.assign_role_or_scopes(approver, nil, ["time_off_approvals:write"])
    refute Atlas.Users.admin?(approver)
    {:ok, booking} = TimeOff.report_holiday(dates(), user)
    assert {:ok, rejected} = TimeOff.review_holiday(booking.id, "rejected", approver)
    assert rejected.status == "rejected"
    assert rejected.reviewed_by_id == approver.id
    assert {:ok, _replacement} = TimeOff.report_holiday(dates(), user)
    Roles.set_user_roles(approver, [])
    assert {:error, :forbidden} = TimeOff.review_holiday(booking.id, "approved", approver)
    assert TimeOff.can_approve?(admin)
  end

  test "only the owner and approvers see rejected and cancelled request history", %{admin: admin, user: user} do
    {:ok, booking} = TimeOff.report_holiday(dates(), user)
    {:ok, _} = TimeOff.review_holiday(booking.id, "rejected", admin)
    {:ok, owner_calendar} = TimeOff.calendar(~D[2026-05-01], ~D[2026-05-31], user)
    assert owner_calendar.bookings == []
    assert [%{status: "rejected"}] = owner_calendar.requests
    {:ok, approver_calendar} = TimeOff.calendar(~D[2026-05-01], ~D[2026-05-31], admin)
    assert [%{status: "rejected"}] = approver_calendar.requests
    {:ok, other_calendar} = TimeOff.calendar(~D[2026-05-01], ~D[2026-05-31], user_fixture())
    assert other_calendar.requests == []

    reader = user_fixture()
    AtlasWeb.ConnCase.assign_role_or_scopes(reader, nil, ["time_off_approvals:read"])
    {:ok, reader_calendar} = TimeOff.calendar(~D[2026-05-01], ~D[2026-05-31], reader)
    assert [%{status: "rejected"}] = reader_calendar.requests
    assert {:error, :forbidden} = TimeOff.review_holiday(booking.id, "approved", reader)
  end

  test "executives get approval permission but the built-in member role does not", %{admin: admin} do
    assert TimeOff.can_approve?(admin)
    role = Roles.ensure_member_role!()
    refute "time_off_approvals:write" in role.scopes
    refute "time_off_approvals:read" in role.scopes
  end

  test "a cancelled request cannot be approved", %{admin: admin, user: user} do
    {:ok, booking} = TimeOff.report_holiday(dates(), user)
    {:ok, _} = TimeOff.cancel_holiday(booking.id, user)
    assert {:error, :not_pending} = TimeOff.review_holiday(booking.id, "approved", admin)
  end

  test "validates date order, invalid dates, maximum duration, and inclusive overlaps", %{user: user} do
    assert {:error, %Ecto.Changeset{}} = TimeOff.report_holiday(%{starts_on: "bad", ends_on: "2026-05-01"}, user)
    assert {:error, %Ecto.Changeset{}} = TimeOff.report_holiday(%{starts_on: "2026-05-05", ends_on: "2026-05-01"}, user)
    assert {:error, %Ecto.Changeset{}} = TimeOff.report_holiday(%{starts_on: "2026-01-01", ends_on: "2027-05-01"}, user)
    {:ok, _booking} = TimeOff.report_holiday(dates(), user)
    assert {:error, changeset} = TimeOff.report_holiday(%{starts_on: "2026-05-05", ends_on: "2026-05-06"}, user)
    assert "overlaps an existing holiday" in errors_on(changeset).starts_on
    assert {:ok, _booking} = TimeOff.report_holiday(%{starts_on: "2026-05-06", ends_on: "2026-05-06"}, user)
  end

  test "cancellation is owner-only, durable, audited, and frees the dates", %{user: user} do
    {:ok, booking} = TimeOff.report_holiday(dates(), user, interface: "mcp")
    assert {:error, :forbidden} = TimeOff.cancel_holiday(booking.id, user_fixture())
    assert {:error, :not_found} = TimeOff.cancel_holiday("not-an-id", user)
    assert {:ok, cancelled} = TimeOff.cancel_holiday(booking.id, user, interface: "mcp")
    assert cancelled.status == "cancelled"
    assert cancelled.cancelled_at
    assert Repo.get!(Booking, booking.id).status == "cancelled"
    assert {:error, :not_active} = TimeOff.cancel_holiday(booking.id, user)
    assert {:ok, _booking} = TimeOff.report_holiday(dates(), user)
    event = Repo.get_by!(Activity, action: "time_off.cancelled", target_id: booking.id)
    assert event.actor_id == user.id
    assert event.interface == "mcp"
    assert event.metadata["path"] == "/people/time-off"
  end

  test "counts exclude weekends and only the booking's location holidays, once per date", %{
    admin: admin,
    user: user,
    location: location
  } do
    other = location_fixture(admin)
    {:ok, _holiday} = TimeOff.add_holiday(location.id, %{name: "May Day", date: "2026-05-01"}, admin)
    {:ok, _holiday} = TimeOff.add_holiday(location.id, %{name: "Same date", date: "2026-05-01"}, admin)
    {:ok, _holiday} = TimeOff.add_holiday(other.id, %{name: "Other location", date: "2026-05-04"}, admin)
    {:ok, _booking} = TimeOff.report_holiday(dates(), user)
    {:ok, data} = TimeOff.calendar(~D[2026-05-01], ~D[2026-05-31])
    assert [%{working_days: 2, missing_years: [2026]}] = data.bookings
  end

  test "calendar includes month-spanning leave with its whole duration and original location", %{
    admin: admin,
    user: user,
    location: location
  } do
    {:ok, _booking} = TimeOff.report_holiday(%{starts_on: "2026-04-30", ends_on: "2026-05-05"}, user)
    new_location = location_fixture(admin)
    assign_fixture(user, new_location, admin)
    {:ok, data} = TimeOff.calendar(~D[2026-05-01], ~D[2026-05-31])
    assert [%{location_id: location_id, working_days: 4}] = data.bookings
    assert location_id == location.id
    assert {:error, :invalid_date_range} = TimeOff.calendar(~D[2026-01-01], ~D[2027-01-01])
    assert {:error, :invalid_date_range} = TimeOff.calendar(~D[2026-05-02], ~D[2026-05-01])
  end

  test "calendar management requires admin rights in the context, not only in adapters", %{
    user: user,
    location: location
  } do
    assert {:error, :forbidden} = TimeOff.create_location(%{name: "Denied", country_code: "DE"}, user)
    assert {:error, :forbidden} = TimeOff.assign_location(user.id, location.id, user)
    assert {:error, :forbidden} = TimeOff.add_holiday(location.id, %{name: "Denied", date: "2026-05-01"}, user)
    assert {:error, :forbidden} = TimeOff.remove_holiday("bad-id", user)
    assert {:error, :forbidden} = TimeOff.import_holidays(location.id, 2026, user)
  end

  test "imports replace one year atomically and preserve manual dates and other years", %{
    admin: admin,
    location: location
  } do
    {:ok, manual} = TimeOff.add_holiday(location.id, %{name: "Local day", date: "2026-05-04"}, admin)
    expect(PublicHolidays, :fetch, fn _location, 2025 -> {:ok, [%{name: "Old year", date: ~D[2025-05-01]}]} end)
    {:ok, _location} = TimeOff.import_holidays(location.id, 2025, admin)
    expect(PublicHolidays, :fetch, fn _location, 2026 -> {:ok, [%{name: "May Day", date: ~D[2026-05-01]}]} end)
    {:ok, _location} = TimeOff.import_holidays(location.id, 2026, admin)
    expect(PublicHolidays, :fetch, fn _location, 2026 -> {:ok, [%{name: "Corrected", date: ~D[2026-05-02]}]} end)
    assert {:ok, updated} = TimeOff.import_holidays(location.id, 2026, admin)
    assert updated.synced_years == [2025, 2026]
    holidays = TimeOff.list_holidays(~D[2025-01-01], ~D[2026-12-31])
    assert Enum.find(holidays, &(&1.id == manual.id))
    assert Enum.any?(holidays, &(&1.name == "Old year"))
    assert Enum.any?(holidays, &(&1.name == "Corrected"))
    refute Enum.any?(holidays, &(&1.name == "May Day"))

    expect(PublicHolidays, :fetch, fn _location, 2026 -> {:error, :holiday_provider_unavailable} end)
    assert {:error, :holiday_provider_unavailable} = TimeOff.import_holidays(location.id, 2026, admin)
    assert length(TimeOff.list_holidays(~D[2025-01-01], ~D[2026-12-31])) == 3
  end

  test "public holiday editing validates dates and prevents exact duplicates", %{admin: admin, location: location} do
    assert {:error, %Ecto.Changeset{}} = TimeOff.add_holiday(location.id, %{name: "Bad date", date: "bad"}, admin)

    assert {:error, %Ecto.Changeset{}} =
             TimeOff.add_holiday(location.id, %{name: "Out of range", date: "1999-12-31"}, admin)

    attrs = %{name: "Local day", date: "2026-05-04"}
    assert {:ok, holiday} = TimeOff.add_holiday(location.id, attrs, admin)
    assert {:error, %Ecto.Changeset{}} = TimeOff.add_holiday(location.id, attrs, admin)
    assert {:ok, _holiday} = TimeOff.remove_holiday(holiday.id, admin)
    assert TimeOff.list_holidays(~D[2026-05-01], ~D[2026-05-31]) == []
  end

  test "invalid imports roll back replacement and coverage", %{admin: admin, location: location} do
    expect(PublicHolidays, :fetch, fn _location, 2026 -> {:ok, [%{name: "", date: ~D[2026-05-01]}]} end)
    assert {:error, %Ecto.Changeset{}} = TimeOff.import_holidays(location.id, 2026, admin)
    assert hd(TimeOff.list_locations()).synced_years == []
  end

  test "changing approved dates clears approval and audits the original request", %{
    admin: admin,
    user: user,
    location: location
  } do
    {:ok, booking} = TimeOff.report_holiday(dates(), user)
    {:ok, _} = TimeOff.review_holiday(booking.id, "approved", admin)

    {:ok, changed} =
      TimeOff.update_holiday(
        booking.id,
        %{starts_on: "2026-05-11", ends_on: "2026-05-15", status: "approved", user_id: admin.id},
        user,
        interface: "mcp"
      )

    assert changed.status == "pending"
    assert changed.reviewed_by_id == nil
    assert changed.reviewed_at == nil
    assert changed.user_id == user.id
    assert changed.location_id == location.id
    assert changed.starts_on == ~D[2026-05-11]
    event = Repo.get_by!(Activity, action: "time_off.updated", target_id: booking.id)
    assert event.interface == "mcp"
    assert event.actor_id == user.id
    assert event.metadata["previous"]["status"] == "approved"
    assert event.metadata["previous"]["starts_on"] == "2026-05-01"
    assert event.metadata["previous"]["reviewed_by_id"] == admin.id
  end

  test "editing is owner-only, including for administrators", %{admin: admin, user: user} do
    {:ok, booking} = TimeOff.report_holiday(dates(), user)
    assert TimeOff.get_my_request(booking.id, admin) == nil
    assert TimeOff.get_my_request("invalid", user) == nil
    assert TimeOff.get_my_request(booking.id, user).id == booking.id
    assert {:error, :not_found} = TimeOff.update_holiday(booking.id, %{ends_on: "2026-05-08"}, admin)
    assert {:error, :not_found} = TimeOff.update_holiday("invalid", %{}, user)
  end

  test "edits validate dates and overlaps but exclude the edited request itself", %{user: user} do
    {:ok, booking} = TimeOff.report_holiday(dates(), user)
    {:ok, _other} = TimeOff.report_holiday(%{starts_on: "2026-05-11", ends_on: "2026-05-15"}, user)
    assert {:ok, _} = TimeOff.update_holiday(booking.id, %{ends_on: "2026-05-06"}, user)
    assert {:error, changeset} = TimeOff.update_holiday(booking.id, %{ends_on: "2026-05-11"}, user)
    assert "overlaps an existing holiday" in errors_on(changeset).starts_on
    assert {:error, %Ecto.Changeset{}} = TimeOff.update_holiday(booking.id, %{ends_on: "2026-04-01"}, user)
    assert TimeOff.get_my_request(booking.id, user).ends_on == ~D[2026-05-06]
  end

  test "saving unchanged approved dates preserves review but rejected requests can be resubmitted", %{
    admin: admin,
    user: user
  } do
    {:ok, booking} = TimeOff.report_holiday(dates(), user)
    {:ok, approved} = TimeOff.review_holiday(booking.id, "approved", admin)
    assert {:ok, unchanged} = TimeOff.update_holiday(booking.id, dates(), user)
    assert unchanged.status == "approved"
    assert unchanged.reviewed_at == approved.reviewed_at
    {:ok, _} = TimeOff.cancel_holiday(booking.id, user)
    assert {:error, :not_active} = TimeOff.update_holiday(booking.id, dates(), user)
    {:ok, rejected} = TimeOff.report_holiday(dates(), user)
    {:ok, _} = TimeOff.review_holiday(rejected.id, "rejected", admin)
    assert {:ok, pending} = TimeOff.update_holiday(rejected.id, dates(), user)
    assert pending.status == "pending"
    assert pending.reviewed_at == nil
  end

  test "editing preserves the original location after reassignment", %{admin: admin, user: user, location: location} do
    {:ok, booking} = TimeOff.report_holiday(dates(), user)
    assign_fixture(user, location_fixture(admin), admin)
    {:ok, changed} = TimeOff.update_holiday(booking.id, %{ends_on: "2026-05-08"}, user)
    assert changed.location_id == location.id
  end

  test "overview paginates future and ongoing team leave separately from private request history", %{
    admin: admin,
    user: user,
    location: location
  } do
    today = Date.utc_today()
    {:ok, past} = TimeOff.report_holiday(%{starts_on: Date.add(today, -20), ends_on: Date.add(today, -18)}, user)
    {:ok, own} = TimeOff.report_holiday(%{starts_on: Date.add(today, 30), ends_on: Date.add(today, 32)}, user)
    teammate = assign_fixture(user_fixture(), location, admin)
    {:ok, ongoing} = TimeOff.report_holiday(%{starts_on: Date.add(today, -1), ends_on: Date.add(today, 2)}, teammate)
    {:ok, _} = TimeOff.add_holiday(location.id, %{name: "Upcoming", date: Date.add(today, 5)}, admin)
    {:ok, _} = TimeOff.add_holiday(location.id, %{name: "Past", date: Date.add(today, -1)}, admin)

    data = TimeOff.overview(user, page_size: 1, location_id: location.id)
    assert [%{id: ongoing_id}] = data.upcoming
    assert ongoing_id == ongoing.id
    assert data.upcoming_meta.total_count == 2
    assert data.mine_meta.total_count == 2
    assert [%{name: "Upcoming"}] = data.public_holidays
    second = TimeOff.overview(user, page_size: 1, upcoming_page: 2, requests_page: 2)
    assert [%{id: own_id}] = second.upcoming
    assert own_id == own.id
    assert [%{id: past_id}] = second.mine
    assert past_id == past.id
    refute Enum.any?(TimeOff.overview(teammate).mine, &(&1.user_id == user.id))
  end

  test "overview location filters never hide a person's own requests", %{admin: admin, user: user} do
    {:ok, _} = TimeOff.report_holiday(dates(), user)
    other_location = location_fixture(admin)
    data = TimeOff.overview(user, from: ~D[2026-05-01], location_id: other_location.id)
    assert data.upcoming == []
    assert length(data.mine) == 1
    assert TimeOff.overview(user, location_id: "invalid", upcoming_page: "bad").upcoming == []
    assert TimeOff.overview(user, requests_page: "99999999999999999999999").mine_meta.current_page == 1
  end

  defp dates, do: %{starts_on: "2026-05-01", ends_on: "2026-05-05"}
end
