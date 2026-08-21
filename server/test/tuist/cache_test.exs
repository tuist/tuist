defmodule Tuist.CacheTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
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

  describe "issue_cache_token/2" do
    # `?full_handle=` reaches here as an empty string when a shell variable is
    # unset. Filtering by it would mint a token granting nothing, which fails on
    # the cache node with nothing pointing back at the exchange.
    test "treats a blank scope as no scope" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "blank-scope-org", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      project = ProjectsFixtures.project_fixture(account: organization.account)

      {:ok, _token, claims} = Cache.issue_cache_token(user, scope: "")

      assert "#{organization.account.name}/#{project.name}" in claims["cache_grants"]["project"]["read"]
    end

    test "treats a whitespace-only scope as no scope" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "ws-scope-org", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      project = ProjectsFixtures.project_fixture(account: organization.account)

      {:ok, _token, claims} = Cache.issue_cache_token(user, scope: "   ")

      assert "#{organization.account.name}/#{project.name}" in claims["cache_grants"]["project"]["read"]
    end

    test "carries the grants for the project the credential reaches" do
      # Given
      project = ProjectsFixtures.project_fixture(preload: [:account])
      handle = "#{project.account.name}/#{project.name}"

      # When
      {:ok, token, _claims} = Cache.issue_cache_token(project)

      # Then
      {:ok, claims} = Tuist.CacheGuardian.decode_and_verify(token)
      assert claims["cache_grants"]["project"]["read"] == [handle]
      assert claims["cache_grants"]["project"]["write"] == [handle]
      assert claims["cache_grants"]["account"] == %{"read" => [], "write" => []}
    end

    # Installing the key is the first of two rollout steps and must be inert on
    # its own. If it also switched issuance on, a replica that had picked up the
    # key would mint tokens the replicas behind it cannot verify.
    test "is signed with the API-credential key until issuance is switched on" do
      # Given
      stub(Tuist.Environment, :cache_token_signing_enabled?, fn -> false end)
      project = ProjectsFixtures.project_fixture()

      # When
      {:ok, token, _claims} = Cache.issue_cache_token(project)

      # Then
      assert Tuist.CacheGuardian.configured?()
      assert {:ok, _} = Tuist.Guardian.decode_and_verify(token)
    end

    # Cache nodes hold the public half of the cache-token pair, so whatever
    # signs a cache token is readable by every node. It must therefore not be
    # the key that signs API credentials, or a node could mint those too.
    test "is not signed with the key that signs API credentials" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      {:ok, token, _claims} = Cache.issue_cache_token(project)

      # Then
      assert {:error, :invalid_token} = Tuist.Guardian.decode_and_verify(token)
      assert {:ok, _} = Tuist.CacheGuardian.decode_and_verify(token)
    end

    # A cache token is handed to cache nodes, which are a different trust
    # boundary from this API. Minting one must not hand out an API credential.
    test "is rejected as an API credential" do
      # Given
      project = ProjectsFixtures.project_fixture()
      {:ok, token, _claims} = Cache.issue_cache_token(project)

      # When
      subject = Tuist.Authentication.authenticated_subject(token)

      # Then
      assert is_nil(subject)
    end

    # Account tokens, the replacement for project tokens, usually reach every
    # project their account owns. Carrying all of them outgrows a request header,
    # so a caller that names its target gets a token sized to that project alone.
    test "narrows the grants to the requested project" do
      # Given
      organization = AccountsFixtures.organization_fixture(preload: [:account])

      projects =
        for _ <- 1..5 do
          ProjectsFixtures.project_fixture(account: organization.account, preload: [:account])
        end

      target = Enum.at(projects, 2)
      handle = "#{target.account.name}/#{target.name}"

      subject = %AuthenticatedAccount{
        account: organization.account,
        scopes: ["project:cache:read", "project:cache:write"],
        all_projects: true
      }

      # When
      {:ok, _token, claims} = Cache.issue_cache_token(subject, scope: handle)

      # Then
      assert claims["cache_grants"]["project"]["read"] == [handle]
      assert claims["cache_grants"]["project"]["write"] == [handle]
    end

    # A cache node authorizes a request naming no project against the account
    # bucket alone, so leaving the target's own account in it would hand a token
    # minted for one project its account's cache as well.
    test "drops account grants when narrowing to a project" do
      # Given
      organization = AccountsFixtures.organization_fixture(preload: [:account])

      project =
        ProjectsFixtures.project_fixture(account: organization.account, preload: [:account])

      handle = "#{project.account.name}/#{project.name}"

      subject = %AuthenticatedAccount{
        account: organization.account,
        scopes: [
          "account:cache:read",
          "account:cache:write",
          "project:cache:read",
          "project:cache:write"
        ],
        all_projects: true
      }

      # When
      {:ok, _token, unscoped} = Cache.issue_cache_token(subject)
      {:ok, _token, scoped} = Cache.issue_cache_token(subject, scope: handle)

      # Then
      assert unscoped["cache_grants"]["account"]["write"] == [organization.account.name]
      assert scoped["cache_grants"]["account"]["read"] == []
      assert scoped["cache_grants"]["account"]["write"] == []
      assert scoped["cache_grants"]["project"]["read"] == [handle]
      assert scoped["cache_grants"]["project"]["write"] == [handle]
    end

    test "never widens the grants beyond what the credential reaches" do
      # Given
      organization = AccountsFixtures.organization_fixture(preload: [:account])
      other = AccountsFixtures.organization_fixture(preload: [:account])
      unreachable = ProjectsFixtures.project_fixture(account: other.account, preload: [:account])

      subject = %AuthenticatedAccount{
        account: organization.account,
        scopes: ["project:cache:read", "project:cache:write"],
        all_projects: true
      }

      # When
      {:ok, _token, claims} =
        Cache.issue_cache_token(subject, scope: "#{unreachable.account.name}/#{unreachable.name}")

      # Then
      assert claims["cache_grants"]["project"]["read"] == []
      assert claims["cache_grants"]["project"]["write"] == []
    end

    test "expires" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      {:ok, token, claims} = Cache.issue_cache_token(project)

      # Then
      assert claims["exp"] - claims["iat"] == Cache.cache_token_ttl_seconds()
      assert {:ok, _} = Tuist.CacheGuardian.decode_and_verify(token)
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
