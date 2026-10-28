defmodule Atlas.TimeOff.PublicHolidaysTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.TimeOff.Location
  alias Atlas.TimeOff.PublicHolidays

  test "imports national and matching regional public holidays but not observances or other regions" do
    expect(Req, :get, fn url, opts ->
      assert url == "https://date.nager.at/api/v3/PublicHolidays/2026/DE"
      assert opts[:redirect] == false

      {:ok,
       %{
         status: 200,
         body: [
           holiday("National", true, nil),
           holiday("Berlin", false, ["DE-BE"]),
           holiday("Bavaria", false, ["DE-BY"]),
           %{holiday("Observance", true, nil) | "types" => ["Observance"]}
         ]
       }}
    end)

    assert {:ok, holidays} = PublicHolidays.fetch(%Location{country_code: "DE", subdivision_code: "DE-BE"}, 2026)
    assert Enum.sort(Enum.map(holidays, & &1.name)) == ["Berlin", "National"]
  end

  test "country-only calendars do not include regional holidays" do
    expect(Req, :get, fn _url, _opts ->
      {:ok, %{status: 200, body: [holiday("National", true, nil), holiday("Berlin", false, ["DE-BE"])]}}
    end)

    assert {:ok, [%{name: "National"}]} = PublicHolidays.fetch(%Location{country_code: "DE"}, 2026)
  end

  test "rejects malformed dates and wrong-year responses instead of partially replacing a calendar" do
    for invalid <- [
          %{holiday("Bad", true, nil) | "date" => "bad"},
          %{holiday("Wrong year", true, nil) | "date" => "2025-05-01"},
          %{"message" => "error"}
        ] do
      expect(Req, :get, fn _url, _opts -> {:ok, %{status: 200, body: [holiday("Valid", true, nil), invalid]}} end)
      assert {:error, :invalid_holiday_response} = PublicHolidays.fetch(%Location{country_code: "DE"}, 2026)
    end
  end

  test "provider failures return a sanitized error" do
    expect(Req, :get, fn _url, _opts -> {:ok, %{status: 429, body: "not exposed"}} end)
    assert {:error, :holiday_provider_unavailable} = PublicHolidays.fetch(%Location{country_code: "DE"}, 2026)
  end

  defp holiday(name, global, counties),
    do: %{"date" => "2026-05-01", "name" => name, "types" => ["Public"], "global" => global, "counties" => counties}
end
