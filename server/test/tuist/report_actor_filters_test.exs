defmodule Tuist.ReportActorFiltersTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Builds
  alias Tuist.Gradle
  alias Tuist.ReportActor
  alias Tuist.Tests
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  test "historical detail lookups retain their account attribution" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    {:ok, build} = RunsFixtures.build_fixture(project_id: project.id, user_id: user.account.id)
    {:ok, run} = RunsFixtures.test_fixture(project_id: project.id, account_id: user.account.id)
    {:ok, build} = Builds.get_build(build.id)
    {:ok, run} = Tests.get_test(run.id)
    assert %{source: :legacy, name: name} = ReportActor.actor(build)
    assert name == user.account.name
    assert %{source: :legacy, name: ^name} = ReportActor.actor(run)
  end

  test "verified user filters preserve legacy rows but cannot be matched by a claim or publisher account" do
    actor = AccountsFixtures.user_fixture(preload: [:account])
    organization = AccountsFixtures.organization_fixture()
    project = ProjectsFixtures.project_fixture(account_id: organization.account.id, build_system: :gradle)
    legacy = GradleFixtures.build_fixture(project_id: project.id, account_id: actor.account.id)

    verified =
      GradleFixtures.build_fixture(
        project_id: project.id,
        account_id: organization.account.id,
        actor_account_id: actor.account.id,
        claimed_actor_id: "workstation",
        submission_auth: "token"
      )

    claimed =
      GradleFixtures.build_fixture(
        project_id: project.id,
        account_id: actor.account.id,
        claimed_actor_id: actor.account.name,
        submission_auth: "token"
      )

    {builds, _} =
      Gradle.list_builds(project.id, %{filters: [%{field: :verified_actor, op: :==, value: actor.account.id}]})

    assert MapSet.new(Enum.map(builds, & &1.id)) == MapSet.new([legacy, verified])

    {builds, _} =
      Gradle.list_builds(project.id, %{filters: [%{field: :claimed_actor_id, op: :==, value: actor.account.name}]})

    assert [%{id: ^claimed}] = builds

    {builds, _} =
      Gradle.list_builds(project.id, %{filters: [%{field: :verified_actor, op: :!=, value: actor.account.id}]})

    assert [%{id: ^claimed}] = builds
  end
end
