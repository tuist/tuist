defmodule Tuist.OAuth.IntrospectionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Cache
  alias Tuist.OAuth.Introspection
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "token_response/1" do
    test "returns inactive for unknown tokens" do
      assert Introspection.token_response("unknown-token") == %{active: false}
    end

    # Every managed cache node authenticates as the control-plane client and so
    # lands here whenever it cannot read the token itself. Answering inactive
    # made it deny every request from a CLI that sends one.
    test "answers a cache token from the grants it carries" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "control-plane-org", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      project = ProjectsFixtures.project_fixture(account: organization.account)
      full_handle = "#{organization.account.name}/#{project.name}"

      {:ok, token, _claims} = Cache.issue_cache_token(user, scope: full_handle)

      assert %{
               active: true,
               cache_grants: %{
                 "project" => %{"read" => project_reads, "write" => project_writes}
               }
             } = Introspection.token_response(token)

      assert full_handle in project_reads
      assert full_handle in project_writes
    end

    # A cache token outlives the deploy that minted it, so the key it was signed
    # with has to keep answering for its whole lifetime. Without this every build
    # holding a token from the previous release is cut off mid-flight.
    test "answers a cache token signed with the API-credential key" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "overlap-org", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      project = ProjectsFixtures.project_fixture(account: organization.account)
      full_handle = "#{organization.account.name}/#{project.name}"

      grants = %{
        "account" => %{"read" => [], "write" => []},
        "project" => %{"read" => [full_handle], "write" => [full_handle]}
      }

      {:ok, token, _claims} =
        Tuist.Guardian.encode_and_sign(user, %{"cache_grants" => grants},
          token_type: "cache",
          ttl: {Cache.cache_token_ttl_seconds(), :second}
        )

      assert %{active: true, cache_grants: %{"project" => %{"read" => reads}}} =
               Introspection.token_response(token)

      assert full_handle in reads
    end

    # The skew this rollout's two steps exist to close. Installing the key and
    # switching on issuance are separate rollouts, so partway through the second
    # one a replica still signing with the old key receives, for introspection,
    # a token a replica ahead of it has already signed with the new one. It
    # holds the key from the first step, so it answers rather than reporting a
    # valid token inactive and 401ing a request that was fine.
    test "answers a cache token signed by a replica already issuing them" do
      stub(Tuist.Environment, :cache_token_signing_enabled?, fn -> false end)

      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "skew-org", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      project = ProjectsFixtures.project_fixture(account: organization.account)
      full_handle = "#{organization.account.name}/#{project.name}"

      refute Tuist.CacheGuardian.signing?()
      assert Tuist.CacheGuardian.configured?()

      grants = %{
        "account" => %{"read" => [], "write" => []},
        "project" => %{"read" => [full_handle], "write" => [full_handle]}
      }

      {:ok, token, _claims} =
        Tuist.CacheGuardian.encode_and_sign(user, %{"cache_grants" => grants},
          token_type: "cache",
          ttl: {Cache.cache_token_ttl_seconds(), :second}
        )

      assert %{active: true, cache_grants: %{"project" => %{"read" => reads}}} =
               Introspection.token_response(token)

      assert full_handle in reads
    end

    # The tenant-scoped path narrows to one account. This one serves every
    # tenant, so a token minted for a project in one organization has to come
    # back carrying that project rather than being filtered to nothing.
    test "answers a cache token whatever tenant it was minted for" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      first = AccountsFixtures.organization_fixture(name: "first-tenant", creator: user)
      second = AccountsFixtures.organization_fixture(name: "second-tenant", creator: user)
      Accounts.add_user_to_organization(user, first, role: :admin)
      Accounts.add_user_to_organization(user, second, role: :admin)
      ProjectsFixtures.project_fixture(account: first.account, name: "ios")
      ProjectsFixtures.project_fixture(account: second.account, name: "android")

      for handle <- ["first-tenant/ios", "second-tenant/android"] do
        {:ok, token, _claims} = Cache.issue_cache_token(user, scope: handle)

        assert %{active: true, cache_grants: %{"project" => %{"read" => reads}}} =
                 Introspection.token_response(token)

        assert handle in reads
      end
    end

    # The refusal answering a cache token depends on: resolving one as a subject
    # would make a token minted for the cache work on every API endpoint, and its
    # `sub` is a project id that the user lookup would read as a user id.
    test "a cache token still resolves to no API subject" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "no-api-control-plane", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      ProjectsFixtures.project_fixture(account: organization.account)

      {:ok, token, _claims} = Cache.issue_cache_token(user)

      assert Tuist.Authentication.authenticated_subject(token) == nil
    end

    test "reports a tampered cache token inactive" do
      assert Introspection.token_response("not.a.jwt") == %{active: false}
    end

    test "returns user cache grants for personal and organization accounts" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "acme-org", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      project = ProjectsFixtures.project_fixture(account: organization.account)

      response = Introspection.token_response(user.token)

      assert %{
               active: true,
               iss: issuer,
               principal_kind: "user",
               sub: user_id,
               username: user_email,
               cache_grants: %{
                 "account" => %{"read" => account_reads, "write" => account_writes},
                 "project" => %{"read" => project_reads, "write" => project_writes}
               }
             } = response

      refute Map.has_key?(response, :scope)
      assert issuer == configured_issuer()
      assert user_id == to_string(user.id)
      assert user_email == user.email
      assert Enum.sort(account_reads) == Enum.sort([user.account.name, organization.account.name])
      assert Enum.sort(account_writes) == Enum.sort([user.account.name, organization.account.name])
      assert project_reads == ["#{organization.account.name}/#{project.name}"]
      assert project_writes == ["#{organization.account.name}/#{project.name}"]
    end

    test "returns read-only user grants for accounts that restrict cache writes to tokens" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "read-only-org", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      {:ok, account} = Accounts.update_account(organization.account, %{cache_write_policy: :tokens_only})
      project = ProjectsFixtures.project_fixture(account: account)

      assert %{
               active: true,
               principal_kind: "user",
               cache_grants: %{
                 "account" => %{"read" => account_reads, "write" => account_writes},
                 "project" => %{"read" => project_reads, "write" => project_writes}
               }
             } = Introspection.token_response(user.token)

      project_handle = "#{account.name}/#{project.name}"

      assert account.name in account_reads
      refute account.name in account_writes
      assert project_handle in project_reads
      refute project_handle in project_writes
    end

    test "keeps project-only account tokens scoped to selected projects" do
      organization = AccountsFixtures.organization_fixture(name: "project-only-org")
      project = ProjectsFixtures.project_fixture(account: organization.account)

      {:ok, {_token, token_value}} =
        Accounts.create_account_token(
          %{
            account: organization.account,
            name: "project-cache",
            scopes: ["project:cache:read"],
            all_projects: false,
            project_ids: [project.id]
          },
          preload: [:account]
        )

      assert %{
               active: true,
               principal_kind: "account",
               scope: "project:cache:read",
               username: "project-only-org",
               cache_grants: %{
                 "account" => %{"read" => [], "write" => []},
                 "project" => %{"read" => project_reads, "write" => []}
               }
             } = Introspection.token_response(token_value)

      assert project_reads == ["#{organization.account.name}/#{project.name}"]
    end

    test "keeps write grants for scoped account tokens when cache writes are restricted to tokens" do
      organization = AccountsFixtures.organization_fixture(name: "token-writer-org")
      {:ok, account} = Accounts.update_account(organization.account, %{cache_write_policy: :tokens_only})
      project = ProjectsFixtures.project_fixture(account: account)

      {:ok, {_token, token_value}} =
        Accounts.create_account_token(
          %{
            account: account,
            name: "ci-cache",
            scopes: ["project:cache:write"],
            all_projects: false,
            project_ids: [project.id]
          },
          preload: [:account]
        )

      assert %{
               active: true,
               principal_kind: "account",
               scope: "project:cache:write",
               cache_grants: %{
                 "account" => %{"read" => [], "write" => []},
                 "project" => %{"read" => project_reads, "write" => project_writes}
               }
             } = Introspection.token_response(token_value)

      project_handle = "#{account.name}/#{project.name}"

      assert project_reads == [project_handle]
      assert project_writes == [project_handle]
    end

    test "returns account cache grants only when account cache scopes are present" do
      organization = AccountsFixtures.organization_fixture(name: "account-cache-org")
      project = ProjectsFixtures.project_fixture(account: organization.account)

      {:ok, {_token, token_value}} =
        Accounts.create_account_token(
          %{
            account: organization.account,
            name: "account-cache",
            scopes: ["account:cache:write", "project:cache:read"],
            all_projects: false,
            project_ids: [project.id]
          },
          preload: [:account]
        )

      assert %{
               active: true,
               principal_kind: "account",
               scope: "account:cache:write project:cache:read",
               cache_grants: %{
                 "account" => %{
                   "read" => ["account-cache-org"],
                   "write" => ["account-cache-org"]
                 },
                 "project" => %{"read" => project_reads, "write" => []}
               }
             } = Introspection.token_response(token_value)

      assert project_reads == ["#{organization.account.name}/#{project.name}"]
    end

    test "returns project cache grants for project tokens" do
      project = ProjectsFixtures.project_fixture()
      token = Projects.create_project_token(project)

      assert %{
               active: true,
               principal_kind: "project",
               scope: "project:cache:read project:cache:write",
               username: project_handle,
               cache_grants: %{
                 "account" => %{"read" => [], "write" => []},
                 "project" => %{"read" => project_reads, "write" => project_writes}
               }
             } = Introspection.token_response(token)

      assert project_handle == "#{project.account.name}/#{project.name}"
      assert project_reads == [project_handle]
      assert project_writes == [project_handle]
    end
  end

  describe "token_response/2 (tenant-scoped)" do
    test "returns inactive for unknown tokens" do
      account = AccountsFixtures.organization_fixture().account
      assert Introspection.token_response("unknown-token", account) == %{active: false}
    end

    # A self-hosted node holds no verifier secret, so an exchanged cache token
    # reaches it as something only we can read. Reporting it inactive makes the
    # node deny every request the CLI exchanged a token for.
    test "answers a cache token from the grants it carries" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "cache-token-org", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      project = ProjectsFixtures.project_fixture(account: organization.account)

      {:ok, token, _claims} = Cache.issue_cache_token(user)

      assert %{
               active: true,
               cache_grants: %{
                 "project" => %{"read" => project_reads}
               }
             } = Introspection.token_response(token, organization.account)

      assert "#{organization.account.name}/#{project.name}" in project_reads
    end

    test "reports a cache token inactive when its grants do not touch the account" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "granted-org", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      ProjectsFixtures.project_fixture(account: organization.account)
      unrelated = AccountsFixtures.organization_fixture(name: "unrelated-org")

      {:ok, token, _claims} = Cache.issue_cache_token(user)

      assert Introspection.token_response(token, unrelated.account) == %{active: false}
    end

    test "reports a tampered cache token inactive" do
      account = AccountsFixtures.organization_fixture().account

      assert Introspection.token_response("not.a.jwt", account) == %{active: false}
    end

    # The whole reason a cache token needs answering here rather than resolving
    # through Guardian: resolving one would make it valid on every API endpoint,
    # and its `sub` is a project id that the user lookup would read as a user id.
    test "a cache token still resolves to no API subject" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "no-api-org", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      ProjectsFixtures.project_fixture(account: organization.account)

      {:ok, token, _claims} = Cache.issue_cache_token(user)

      assert Tuist.Authentication.authenticated_subject(token) == nil
    end

    test "constrains grants to the given account and drops other tenants" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "scoped-org", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      project = ProjectsFixtures.project_fixture(account: organization.account)

      assert %{
               active: true,
               principal_kind: "user",
               cache_grants: %{
                 "account" => %{"read" => account_reads, "write" => account_writes},
                 "project" => %{"read" => project_reads, "write" => project_writes}
               }
             } = Introspection.token_response(user.token, organization.account)

      assert account_reads == [organization.account.name]
      assert account_writes == [organization.account.name]
      assert project_reads == ["#{organization.account.name}/#{project.name}"]
      assert project_writes == ["#{organization.account.name}/#{project.name}"]
    end

    test "returns tenant-scoped read-only user grants when cache writes are restricted to tokens" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "scoped-read-only-org", creator: user)
      Accounts.add_user_to_organization(user, organization, role: :admin)
      {:ok, account} = Accounts.update_account(organization.account, %{cache_write_policy: :tokens_only})
      project = ProjectsFixtures.project_fixture(account: account)

      assert %{
               active: true,
               principal_kind: "user",
               cache_grants: %{
                 "account" => %{"read" => account_reads, "write" => account_writes},
                 "project" => %{"read" => project_reads, "write" => project_writes}
               }
             } = Introspection.token_response(user.token, account)

      assert account_reads == [account.name]
      assert account_writes == []
      assert project_reads == ["#{account.name}/#{project.name}"]
      assert project_writes == []
    end

    test "returns tenant-scoped read-only user-issued OAuth grants when cache writes are restricted to tokens" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(name: "oauth-read-only-org", creator: user)
      {:ok, account} = Accounts.update_account(organization.account, %{cache_write_policy: :tokens_only})
      project = ProjectsFixtures.project_fixture(account: account)

      {:ok, token, _claims} =
        Tuist.Guardian.encode_and_sign(
          user.account,
          %{
            "type" => "account",
            "scopes" => ["account:cache:write", "project:cache:write"],
            "all_projects" => true,
            "user_id" => user.id
          },
          token_type: :access
        )

      assert %{
               active: true,
               principal_kind: "account",
               cache_grants: %{
                 "account" => %{"read" => account_reads, "write" => account_writes},
                 "project" => %{"read" => project_reads, "write" => project_writes}
               }
             } = Introspection.token_response(token, account)

      assert account_reads == [account.name]
      assert account_writes == []
      assert project_reads == ["#{account.name}/#{project.name}"]
      assert project_writes == []
    end

    test "rejects user-issued OAuth grants for an unrelated tenant" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      unrelated = AccountsFixtures.organization_fixture(name: "oauth-unrelated-org")

      {:ok, token, _claims} =
        Tuist.Guardian.encode_and_sign(
          user.account,
          %{
            "type" => "account",
            "scopes" => ["account:cache:read", "project:cache:read"],
            "all_projects" => true,
            "user_id" => user.id
          },
          token_type: :access
        )

      assert Introspection.token_response(token, unrelated.account) == %{active: false}
    end

    test "returns inactive when the token has no grant for the account" do
      user = AccountsFixtures.user_fixture(preload: [:account])
      unrelated = AccountsFixtures.organization_fixture(name: "unrelated-org")

      assert Introspection.token_response(user.token, unrelated.account) == %{active: false}
    end

    test "scopes project tokens to their own account" do
      project = ProjectsFixtures.project_fixture()
      token = Projects.create_project_token(project)
      other = AccountsFixtures.organization_fixture(name: "other-tenant-org")

      assert %{active: true, principal_kind: "project"} =
               Introspection.token_response(token, project.account)

      assert Introspection.token_response(token, other.account) == %{active: false}
    end
  end

  defp configured_issuer do
    :tuist
    |> Application.fetch_env!(Tuist.Guardian)
    |> Keyword.fetch!(:issuer)
  end
end
