defmodule Tuist.OIDC.ScopeRulesTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.OIDC.ScopeRule
  alias Tuist.OIDC.ScopeRules
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @main_claims %{
    provider: :github_actions,
    ref: "refs/heads/main",
    job_workflow_ref: "tuist/tuist/.github/workflows/release.yml@refs/heads/main",
    environment: "production"
  }

  describe "pattern_matches?/2" do
    test "matches literals exactly and case-sensitively" do
      assert ScopeRules.pattern_matches?("refs/heads/main", "refs/heads/main")
      refute ScopeRules.pattern_matches?("refs/heads/main", "refs/heads/main-2")
      refute ScopeRules.pattern_matches?("refs/heads/main", "refs/heads/Main")
    end

    test "* matches within a single path segment" do
      assert ScopeRules.pattern_matches?("refs/heads/release/*", "refs/heads/release/1.0")
      refute ScopeRules.pattern_matches?("refs/heads/release/*", "refs/heads/release/1.0/hotfix")
      assert ScopeRules.pattern_matches?("refs/tags/v*", "refs/tags/v1.2.3")
    end

    test "** matches across path segments" do
      assert ScopeRules.pattern_matches?("refs/heads/release/**", "refs/heads/release/1.0/hotfix")

      assert ScopeRules.pattern_matches?(
               "tuist/tuist/.github/workflows/release.yml@**",
               "tuist/tuist/.github/workflows/release.yml@refs/heads/main"
             )
    end

    test "treats regular expression characters literally" do
      assert ScopeRules.pattern_matches?("tuist/tuist/.github/workflows/a.yml", "tuist/tuist/.github/workflows/a.yml")
      refute ScopeRules.pattern_matches?("tuist/tuist/.github/workflows/a.yml", "tuist/tuist/.github/workflows/aXyml")
    end
  end

  describe "match/2" do
    test "passes when every configured field matches" do
      rule = %ScopeRule{refs: ["refs/heads/main"], job_workflow_refs: [], environments: ["production"]}

      assert :ok = ScopeRules.match(rule, @main_claims)
    end

    test "reports the first field that doesn't match" do
      rule = %ScopeRule{refs: ["refs/heads/main"], job_workflow_refs: [], environments: ["production"]}

      assert {:error, :ref, "refs/heads/feature"} =
               ScopeRules.match(rule, %{@main_claims | ref: "refs/heads/feature"})
    end

    test "fails a configured field when the claim is missing" do
      rule = %ScopeRule{refs: [], job_workflow_refs: [], environments: ["production"]}

      assert {:error, :environment, nil} = ScopeRules.match(rule, Map.delete(@main_claims, :environment))
    end

    test "fails any rule for tokens from providers other than GitHub Actions" do
      rule = %ScopeRule{refs: ["**"], job_workflow_refs: [], environments: []}

      assert {:error, :provider, :circleci} = ScopeRules.match(rule, %{provider: :circleci})
    end
  end

  describe "evaluate/3" do
    test "withholds a scope only for the projects whose rules don't match" do
      strict = ProjectsFixtures.project_fixture(preload: [:account])
      open = ProjectsFixtures.project_fixture(account_id: strict.account_id, preload: [:account])

      {:ok, _} = ScopeRules.put_project_rule(strict, "project:previews:write", %{refs: ["refs/heads/main"]})

      assert {%{"project:previews:write" => [strict_id]}, [failure]} =
               ScopeRules.evaluate(strict.account, [strict, open], %{@main_claims | ref: "refs/heads/feature"})

      assert strict_id == strict.id
      assert %{scope: "project:previews:write", level: :project, field: :ref, value: "refs/heads/feature"} = failure
      assert failure.project.id == strict.id
    end

    test "withholds account scopes by account id" do
      project = ProjectsFixtures.project_fixture(preload: [:account])
      {:ok, _} = ScopeRules.put_account_rule(project.account, "account:cache:write", %{environments: ["production"]})

      assert {%{"account:cache:write" => [account_id]}, [%{level: :account, field: :environment}]} =
               ScopeRules.evaluate(project.account, [project], Map.delete(@main_claims, :environment))

      assert account_id == project.account.id
    end

    test "withholds nothing when every rule matches" do
      project = ProjectsFixtures.project_fixture(preload: [:account])
      {:ok, _} = ScopeRules.put_project_rule(project, "project:cache:write", %{refs: ["refs/heads/main"]})
      {:ok, _} = ScopeRules.put_account_rule(project.account, "account:cache:write", %{refs: ["refs/heads/*"]})

      assert {%{}, []} = ScopeRules.evaluate(project.account, [project], @main_claims)
    end

    test "ignores rules of other accounts and projects" do
      project = ProjectsFixtures.project_fixture(preload: [:account])
      other = ProjectsFixtures.project_fixture(preload: [:account])
      {:ok, _} = ScopeRules.put_project_rule(other, "project:cache:write", %{refs: ["refs/heads/nope"]})
      {:ok, _} = ScopeRules.put_account_rule(other.account, "account:cache:write", %{refs: ["refs/heads/nope"]})

      assert {%{}, []} = ScopeRules.evaluate(project.account, [project], @main_claims)
    end
  end

  describe "put_project_rule/3" do
    test "creates and then updates the rule for a scope" do
      project = ProjectsFixtures.project_fixture()

      {:ok, rule} = ScopeRules.put_project_rule(project, "project:cache:write", %{refs: [" refs/heads/main ", ""]})
      assert rule.refs == ["refs/heads/main"]

      {:ok, updated} = ScopeRules.put_project_rule(project, "project:cache:write", %{refs: ["refs/heads/release/*"]})
      assert updated.id == rule.id
      assert [%ScopeRule{refs: ["refs/heads/release/*"]}] = ScopeRules.list_project_rules(project)
    end

    test "rejects a rule without any pattern" do
      project = ProjectsFixtures.project_fixture()

      assert {:error, changeset} = ScopeRules.put_project_rule(project, "project:cache:write", %{refs: [" "]})
      assert "add at least one branch, workflow, or environment pattern" in errors_on(changeset).refs
    end

    test "stores project rules without an account" do
      project = ProjectsFixtures.project_fixture()

      {:ok, rule} = ScopeRules.put_project_rule(project, "project:cache:write", %{refs: ["refs/heads/main"]})

      assert rule.project_id == project.id
      assert is_nil(rule.account_id)
    end

    test "rejects account scopes on a project" do
      project = ProjectsFixtures.project_fixture()

      assert {:error, changeset} =
               ScopeRules.put_project_rule(project, "account:cache:write", %{refs: ["refs/heads/main"]})

      assert errors_on(changeset).scope != []
    end
  end

  describe "put_account_rule/3" do
    test "rejects project scopes on an account" do
      project = ProjectsFixtures.project_fixture(preload: [:account])

      assert {:error, changeset} =
               ScopeRules.put_account_rule(project.account, "project:cache:write", %{refs: ["refs/heads/main"]})

      assert errors_on(changeset).scope != []
    end

    test "keeps account and project rules apart" do
      project = ProjectsFixtures.project_fixture(preload: [:account])
      {:ok, _} = ScopeRules.put_project_rule(project, "project:cache:write", %{refs: ["refs/heads/main"]})
      {:ok, _} = ScopeRules.put_account_rule(project.account, "account:cache:write", %{refs: ["refs/heads/main"]})

      assert [%ScopeRule{scope: "account:cache:write"}] = ScopeRules.list_account_rules(project.account)
      assert [%ScopeRule{scope: "project:cache:write"}] = ScopeRules.list_project_rules(project)

      :ok = ScopeRules.delete_account_rule(project.account, "account:cache:write")
      assert [] = ScopeRules.list_account_rules(project.account)
      assert [_] = ScopeRules.list_project_rules(project)
    end
  end
end
