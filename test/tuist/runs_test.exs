defmodule Tuist.RunsTest do
  alias TuistTestSupport.Fixtures.RunsFixtures
  use TuistTestSupport.Cases.DataCase

  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias Tuist.Runs

  describe "create_build/1" do
    test "creates a build" do
      # Given
      project_id = ProjectsFixtures.project_fixture().id
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      # When
      {:ok, build} =
        Runs.create_build(%{
          id: UUIDv7.generate(),
          duration: 1000,
          macos_version: "11.2.3",
          xcode_version: "12.4",
          is_ci: false,
          model_identifier: "Mac15,6",
          scheme: "App",
          project_id: project_id,
          account_id: account_id
        })

      # Then
      assert build.duration == 1000
      assert build.macos_version == "11.2.3"
      assert build.xcode_version == "12.4"
      assert build.is_ci == false
      assert build.model_identifier == "Mac15,6"
      assert build.scheme == "App"
      assert build.project_id == project_id
      assert build.account_id == account_id
    end
  end

  describe "build/1" do
    test "returns build" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture()

      build_id = build.id

      # When
      build = Runs.get_build(build_id)

      # Then
      assert build.id == build_id
    end

    test "returns nil when build does not exist" do
      # Given
      non_existent_build_id = UUIDv7.generate()

      # When
      build = Runs.get_build(non_existent_build_id)

      # Then
      assert build == nil
    end
  end
end
