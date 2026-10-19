defmodule Atlas.TimeOff.SyncPublicHolidaysTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  import Atlas.TimeOffFixtures

  alias Atlas.Audit.Activity
  alias Atlas.TimeOff
  alias Atlas.TimeOff.PublicHolidays
  alias Atlas.TimeOff.SyncPublicHolidays

  test "startup and daily schedules refresh Berlin for this year and next year" do
    year = Date.utc_today().year

    stub(PublicHolidays, :fetch, fn location, requested_year ->
      assert location.country_code == "DE"
      assert location.subdivision_code == "DE-BE"
      assert requested_year in [year, year + 1]
      {:ok, [%{name: "New Year's Day", date: Date.new!(requested_year, 1, 1)}]}
    end)

    assert :ok = perform_job(SyncPublicHolidays, %{})
    assert :ok = perform_job(SyncPublicHolidays, %{})
    location = TimeOff.default_location()
    assert location.synced_years == [year, year + 1]
    assert length(TimeOff.list_holidays(Date.new!(year, 1, 1), Date.new!(year + 1, 12, 31))) == 2
    assert Enum.all?(Repo.all(Activity), &(&1.interface == "worker" && is_nil(&1.actor_id)))

    crontab =
      :atlas
      |> Application.fetch_env!(Oban)
      |> Keyword.fetch!(:plugins)
      |> Keyword.fetch!(Oban.Plugins.Cron)
      |> Keyword.fetch!(:crontab)

    assert {"@reboot", SyncPublicHolidays} in crontab
    assert {"0 2 * * *", SyncPublicHolidays} in crontab
  end

  test "provider failures retry without removing the previous calendar" do
    year = Date.utc_today().year

    stub(PublicHolidays, :fetch, fn _location, requested_year ->
      {:ok, [%{name: "Holiday", date: Date.new!(requested_year, 1, 1)}]}
    end)

    assert :ok = perform_job(SyncPublicHolidays, %{})
    previous = TimeOff.list_holidays(Date.new!(year, 1, 1), Date.new!(year + 1, 12, 31))
    stub(PublicHolidays, :fetch, fn _, _ -> {:error, :holiday_provider_unavailable} end)
    assert {:error, :holiday_provider_unavailable} = perform_job(SyncPublicHolidays, %{})
    assert previous == TimeOff.list_holidays(Date.new!(year, 1, 1), Date.new!(year + 1, 12, 31))
  end

  test "user-triggered refresh requires administrative write permission" do
    stub(PublicHolidays, :fetch, fn _, _ -> flunk("Unauthorized callers must not fetch holidays") end)
    assert {:error, :forbidden} = TimeOff.sync_public_holidays(actor: user_fixture(), interface: "mcp")
  end
end
