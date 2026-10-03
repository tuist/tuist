defmodule Tuist.Marketing.OverdriveTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Marketing.Overdrive
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "list_projects/0" do
    test "lists curated forks whose Tuist project is public" do
      account = AccountsFixtures.organization_fixture(name: "tuist", preload: [:account]).account
      ProjectsFixtures.project_fixture(account: account, name: "mise", visibility: :public, build_system: :once)

      assert [%{handle: "tuist/mise", upstream_handle: "jdx/mise", stats: stats}] = Overdrive.list_projects()
      assert %{builds: nil, test_runs: nil, cache_hit_rate: nil, median_build_duration_ms: nil} = stats
    end

    test "leaves out curated forks whose Tuist project is private" do
      account = AccountsFixtures.organization_fixture(name: "tuist", preload: [:account]).account
      ProjectsFixtures.project_fixture(account: account, name: "mise", visibility: :private)

      assert Overdrive.list_projects() == []
      assert Overdrive.get_project("tuist", "mise") == {:error, :not_found}
    end

    test "leaves out curated forks without a Tuist project" do
      assert Overdrive.list_projects() == []
    end
  end

  describe "get_project/2" do
    test "doesn't expose public projects that aren't curated" do
      account = AccountsFixtures.organization_fixture(name: "tuist", preload: [:account]).account
      ProjectsFixtures.project_fixture(account: account, name: "tuist", visibility: :public)

      assert Overdrive.get_project("tuist", "tuist") == {:error, :not_found}
    end
  end

  describe "formatting" do
    test "formats counts compactly" do
      assert Overdrive.format_count(nil) == nil
      assert Overdrive.format_count(42) == "42"
      assert Overdrive.format_count(1_000) == "1K"
      assert Overdrive.format_count(12_345) == "12.3K"
      assert Overdrive.format_count(2_500_000) == "2.5M"
    end

    test "formats percentages and durations" do
      assert Overdrive.format_percentage(87.6) == "88%"
      assert Overdrive.format_percentage(nil) == nil
      assert Overdrive.format_duration(400) == "1s"
      assert Overdrive.format_duration(72_000) == "1m 12s"
      assert Overdrive.format_duration(3_900_000) == "1h 5m"
    end
  end
end
