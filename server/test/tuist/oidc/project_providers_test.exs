defmodule Tuist.OIDC.ProjectProvidersTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.OIDC.ProjectProvider
  alias Tuist.OIDC.ProjectProviders
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "record_exchange/2" do
    test "records each provider once per project" do
      project = ProjectsFixtures.project_fixture()

      :ok = ProjectProviders.record_exchange([project], :circleci)
      :ok = ProjectProviders.record_exchange([project], :circleci)
      :ok = ProjectProviders.record_exchange([project], :github_actions)

      assert [:circleci, :github_actions] =
               ProjectProvider |> Repo.all() |> Enum.map(& &1.provider) |> Enum.sort()
    end

    test "refreshes a timestamp only once it is older than an hour" do
      project = ProjectsFixtures.project_fixture()
      :ok = ProjectProviders.record_exchange([project], :bitrise)
      recent = DateTime.add(DateTime.utc_now(:second), -30, :minute)
      old = DateTime.add(DateTime.utc_now(:second), -2, :hour)

      Repo.update_all(ProjectProvider, set: [last_exchanged_at: recent])
      :ok = ProjectProviders.record_exchange([project], :bitrise)
      assert [%{last_exchanged_at: ^recent}] = Repo.all(ProjectProvider)

      Repo.update_all(ProjectProvider, set: [last_exchanged_at: old])
      :ok = ProjectProviders.record_exchange([project], :bitrise)
      assert [%{last_exchanged_at: refreshed}] = Repo.all(ProjectProvider)
      assert DateTime.after?(refreshed, recent)
    end

    test "ignores unknown providers" do
      project = ProjectsFixtures.project_fixture()

      assert :ok = ProjectProviders.record_exchange([project], nil)
      assert [] = Repo.all(ProjectProvider)
    end
  end

  describe "recent_unmatched_providers/2" do
    test "lists recent providers other than GitHub Actions for a project and its account" do
      project = ProjectsFixtures.project_fixture(preload: [:account])
      sibling = ProjectsFixtures.project_fixture(account_id: project.account_id)
      other = ProjectsFixtures.project_fixture()

      :ok = ProjectProviders.record_exchange([project], :github_actions)
      :ok = ProjectProviders.record_exchange([project], :circleci)
      :ok = ProjectProviders.record_exchange([sibling], :bitrise)
      :ok = ProjectProviders.record_exchange([other], :bitrise)

      assert ProjectProviders.recent_unmatched_providers(project) == [:circleci]
      assert ProjectProviders.recent_unmatched_providers(project.account) == [:bitrise, :circleci]
    end

    test "leaves out providers not seen within the window" do
      project = ProjectsFixtures.project_fixture()
      :ok = ProjectProviders.record_exchange([project], :circleci)
      Repo.update_all(ProjectProvider, set: [last_exchanged_at: DateTime.add(DateTime.utc_now(:second), -31, :day)])

      assert ProjectProviders.recent_unmatched_providers(project) == []
    end
  end
end
