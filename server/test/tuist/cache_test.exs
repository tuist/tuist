defmodule Tuist.CacheTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Cache
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "last_24h_artifacts_count/0" do
    test "returns the count from the daily stats view" do
      # Given
      stub(Tuist.ClickHouseRepo, :query, fn _query, _params ->
        {:ok, %{rows: [[42]]}}
      end)

      # When
      count = Cache.last_24h_artifacts_count()

      # Then
      assert count == 42
    end

    test "returns 0 when the query returns nil" do
      # Given
      stub(Tuist.ClickHouseRepo, :query, fn _query, _params ->
        {:ok, %{rows: [[nil]]}}
      end)

      # When
      count = Cache.last_24h_artifacts_count()

      # Then
      assert count == 0
    end

    test "returns 0 when the query fails" do
      # Given
      stub(Tuist.ClickHouseRepo, :query, fn _query, _params ->
        {:error, :timeout}
      end)

      # When
      count = Cache.last_24h_artifacts_count()

      # Then
      assert count == 0
    end
  end

  describe "cache_grants/2" do
    # Kura calls this on every cache authentication that misses its local
    # cache, so its cost has to stay flat in the number of projects an account
    # owns. Resolving the grants used to read each project's account back from
    # the database while deciding whether the subject may use that project's
    # cache, which made the largest accounts the slowest to authorize.
    test "issues the same number of queries regardless of how many projects the account has" do
      # Given
      queries_for = fn project_count ->
        user = AccountsFixtures.user_fixture(preload: [:account])
        organization = AccountsFixtures.organization_fixture(creator: user)
        Accounts.add_user_to_organization(user, organization, role: :admin)

        for _ <- 1..project_count do
          ProjectsFixtures.project_fixture(account: organization.account)
        end

        count_queries(fn -> Cache.cache_grants(user) end)
      end

      # When
      few = queries_for.(2)
      many = queries_for.(12)

      # Then
      assert few == many
    end

    test "still grants every project the subject can reach" do
      # Given
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)

      handles =
        for _ <- 1..12 do
          project = ProjectsFixtures.project_fixture(account: organization.account, preload: [:account])
          "#{project.account.name}/#{project.name}"
        end

      # When
      grants = Cache.cache_grants(user)

      # Then
      assert Enum.sort(grants["project"]["read"]) == Enum.sort(handles)
      assert Enum.sort(grants["project"]["write"]) == Enum.sort(handles)
    end
  end

  # Ecto emits its query telemetry from the process that called the repo, and
  # the handler is global to the node, so the counter only accepts events raised
  # by this test. Without that guard an async run counts every other test's
  # queries too.
  defp count_queries(fun) do
    handler_id = "cache-test-query-counter-#{System.unique_integer([:positive])}"
    counter = :counters.new(1, [])
    test_pid = self()

    :telemetry.attach(
      handler_id,
      [:tuist, :repo, :query],
      fn _event, _measurements, _metadata, _config ->
        if self() == test_pid, do: :counters.add(counter, 1, 1)
      end,
      nil
    )

    try do
      fun.()
      :counters.get(counter, 1)
    after
      :telemetry.detach(handler_id)
    end
  end
end
