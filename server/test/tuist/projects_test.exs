defmodule Tuist.ProjectsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use TuistTestSupport.Cases.StubCase, billing: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.ProjectAccount
  alias Tuist.Base64
  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias Tuist.Projects.ProjectToken
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "get_projects_count/0" do
    test "returns the right count" do
      # Given
      ProjectsFixtures.project_fixture()

      # When
      got = Projects.get_projects_count()

      # Then
      assert got == 1
    end
  end

  describe "get_project_count_for_account/1" do
    test "returns the right count for a specific account" do
      # Given
      user_one = AccountsFixtures.user_fixture()
      user_two = AccountsFixtures.user_fixture()
      account_one = Accounts.get_account_from_user(user_one)
      account_two = Accounts.get_account_from_user(user_two)

      ProjectsFixtures.project_fixture(account_id: account_one.id)
      ProjectsFixtures.project_fixture(account_id: account_one.id)
      ProjectsFixtures.project_fixture(account_id: account_two.id)

      # When
      got = Projects.get_project_count_for_account(account_one)

      # Then
      assert got == 2
    end

    test "returns 0 when account has no projects" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      # When
      got = Projects.get_project_count_for_account(account)

      # Then
      assert got == 0
    end
  end

  test "returns command average duration" do
    # Given
    organization = AccountsFixtures.organization_fixture(name: "tuist")
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(name: "tuist-project", account_id: account.id)

    # When
    {:ok, got} = Projects.get_project_by_slug("tuist/tuist-project")

    # Then
    assert got == project
  end

  test "returns all projects associated with a user" do
    # Given
    organization = AccountsFixtures.organization_fixture()
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id, preload: [:account])
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization, role: :user)
    organization_two = AccountsFixtures.organization_fixture()
    account_two = Accounts.get_account_from_organization(organization_two)
    ProjectsFixtures.project_fixture(account_id: account_two.id)

    # When
    got = Projects.get_all_project_accounts(user)

    # Then
    assert [
             %ProjectAccount{
               handle: "#{account.name}/#{project.name}",
               account: account,
               project: project
             }
           ] == got
  end

  test "returns all projects associated with a user's based on a google hosted domain" do
    # Given
    organization =
      AccountsFixtures.organization_fixture(
        sso_provider: :google,
        sso_organization_id: "tuist.io"
      )

    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    user =
      Accounts.find_or_create_user_from_oauth2(%{
        provider: :google,
        uid: 123,
        info: %{
          email: "tuist@tuist.dev"
        },
        extra: %{
          raw_info: %{
            user: %{
              "hd" => "tuist.io"
            }
          }
        }
      })

    # When
    got = Projects.get_all_project_accounts(user)

    # Then
    assert [
             "#{account.name}/#{project.name}"
           ] == Enum.map(got, & &1.handle)
  end

  test "returns missing handle or project name" do
    assert {:error, :invalid} == Projects.get_project_by_slug("tuist")
  end

  describe "get_project_account_by_project_id/1" do
    test "returns nil if a project does not exist" do
      assert nil == Projects.get_project_account_by_project_id(1)
    end

    test "returns project account" do
      # Given
      organization = AccountsFixtures.organization_fixture(name: "tuist")
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      got = Projects.get_all_project_accounts(account)

      # Then
      assert ["#{account.name}/#{project.name}"] == Enum.map(got, & &1.handle)
    end
  end

  describe "get_project_and_account_handles_from_full_handle/1" do
    test "returns :invalid_full_handle error if full handle contains only one handle" do
      assert {:error, :invalid_full_handle} ==
               Projects.get_project_and_account_handles_from_full_handle("tuist")
    end

    test "returns :invalid_full_handle error if full handle contains only more than two handles" do
      assert {:error, :invalid_full_handle} ==
               Projects.get_project_and_account_handles_from_full_handle("tuist-org/tuist/tuist")
    end

    test "returns project and account handles" do
      assert {:ok, %{account_handle: "tuist-org", project_handle: "tuist"}} ==
               Projects.get_project_and_account_handles_from_full_handle("tuist-org/tuist")
    end
  end

  describe "delete_project/1" do
    test "deletes a project" do
      # Given
      organization = AccountsFixtures.organization_fixture(name: "tuist")
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      command_event =
        CommandEventsFixtures.command_event_fixture(
          name: "generate",
          project_id: project.id
        )

      # When
      Projects.delete_project(project)

      # Then
      assert nil == Projects.get_project_by_id(project.id)
      assert {:error, :not_found} == CommandEvents.get_command_event_by_id(command_event.id)
    end
  end

  describe "get_all_project_accounts/1" do
    test "get all project accounts for an account" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id, preload: [:account])

      # When
      got = Projects.get_all_project_accounts(account)

      # Then
      assert [
               %ProjectAccount{
                 handle: "#{account.name}/#{project.name}",
                 account: account,
                 project: project
               }
             ] == got
    end

    test "get all project accounts for an authenticated account subject" do
      account = AccountsFixtures.account_fixture()
      project_one = ProjectsFixtures.project_fixture(account_id: account.id, preload: [:account])
      project_two = ProjectsFixtures.project_fixture(account_id: account.id, preload: [:account])

      got = Projects.get_all_project_accounts(%AuthenticatedAccount{account: account, scopes: []})

      assert Enum.sort_by(got, & &1.handle) ==
               Enum.sort_by(
                 [
                   %ProjectAccount{
                     handle: "#{account.name}/#{project_one.name}",
                     account: account,
                     project: project_one
                   },
                   %ProjectAccount{
                     handle: "#{account.name}/#{project_two.name}",
                     account: account,
                     project: project_two
                   }
                 ],
                 & &1.handle
               )
    end

    test "get all project accounts for a project subject" do
      project = ProjectsFixtures.project_fixture()

      got = Projects.get_all_project_accounts(project)

      expected_handle = "#{project.account.name}/#{project.name}"
      assert [%ProjectAccount{handle: ^expected_handle}] = got
    end

    test "returns empty list for unsupported subjects" do
      assert [] == Projects.get_all_project_accounts(%{unexpected: :subject})
      assert [] == Projects.get_all_project_accounts(nil)
    end

    test "get all project accounts for a user" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project_one = ProjectsFixtures.project_fixture(account_id: account.id, preload: [:account])
      user = AccountsFixtures.user_fixture()
      user_account = Accounts.get_account_from_user(user)
      Accounts.add_user_to_organization(user, organization, role: :user)

      project_two =
        ProjectsFixtures.project_fixture(account_id: user_account.id, preload: [:account])

      # When
      got = Projects.get_all_project_accounts(user)

      # Then
      assert Enum.sort_by(
               [
                 %ProjectAccount{
                   handle: "#{account.name}/#{project_one.name}",
                   account: account,
                   project: project_one
                 },
                 %ProjectAccount{
                   handle: "#{user_account.name}/#{project_two.name}",
                   account: user_account,
                   project: project_two
                 }
               ],
               & &1.handle
             ) == Enum.sort_by(got, & &1.handle)
    end

    test "filters to most recent projects when recent option is provided" do
      user = AccountsFixtures.user_fixture()
      user_account = Accounts.get_account_from_user(user)

      projects =
        for i <- 1..7 do
          ProjectsFixtures.project_fixture(account_id: user_account.id, name: "project-#{i}")
        end

      [p1, p2, p3, p4, p5, p6, p7] = projects

      now = DateTime.utc_now()
      CommandEventsFixtures.command_event_fixture(project_id: p1.id, created_at: DateTime.add(now, -6, :day))
      CommandEventsFixtures.command_event_fixture(project_id: p2.id, created_at: DateTime.add(now, -5, :day))
      CommandEventsFixtures.command_event_fixture(project_id: p3.id, created_at: DateTime.add(now, -4, :day))
      CommandEventsFixtures.command_event_fixture(project_id: p4.id, created_at: DateTime.add(now, -3, :day))
      CommandEventsFixtures.command_event_fixture(project_id: p5.id, created_at: DateTime.add(now, -2, :day))
      CommandEventsFixtures.command_event_fixture(project_id: p6.id, created_at: DateTime.add(now, -1, :hour))
      CommandEventsFixtures.command_event_fixture(project_id: p7.id, created_at: now)

      got = Projects.get_all_project_accounts(user, recent: 5)

      assert length(got) == 5
      handles = Enum.map(got, & &1.handle)

      assert "#{user_account.name}/#{p7.name}" in handles
      assert "#{user_account.name}/#{p6.name}" in handles
      assert "#{user_account.name}/#{p5.name}" in handles
      assert "#{user_account.name}/#{p4.name}" in handles
      assert "#{user_account.name}/#{p3.name}" in handles

      refute "#{user_account.name}/#{p2.name}" in handles
      refute "#{user_account.name}/#{p1.name}" in handles

      assert Enum.at(got, 0).handle == "#{user_account.name}/#{p7.name}"
    end
  end

  describe "get_project_by_account_and_project_handles/2" do
    test "returns the project if it exists doing a case-insensitive search" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      got =
        Projects.get_project_by_account_and_project_handles(
          String.upcase(account.name),
          String.upcase(project.name)
        )

      # Then
      assert got == project
    end
  end

  describe "get_projects_by_handles_for_account/2" do
    test "returns projects when all handles are found" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project1 = ProjectsFixtures.project_fixture(account_id: account.id, name: "project-one")
      project2 = ProjectsFixtures.project_fixture(account_id: account.id, name: "project-two")

      # When
      {:ok, projects} =
        Projects.get_projects_by_handles_for_account(account, ["project-one", "project-two"])

      # Then
      project_ids = projects |> Enum.map(& &1.id) |> Enum.sort()
      assert project_ids == Enum.sort([project1.id, project2.id])
    end

    test "returns error when a handle is not found" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      ProjectsFixtures.project_fixture(account_id: account.id, name: "existing-project")

      # When
      result =
        Projects.get_projects_by_handles_for_account(account, ["existing-project", "missing-project"])

      # Then
      assert {:error, :not_found, "missing-project"} = result
    end

    test "returns ok with empty list when no handles provided" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)

      # When
      {:ok, projects} = Projects.get_projects_by_handles_for_account(account, [])

      # Then
      assert projects == []
    end

    test "does not return projects from other accounts" do
      # Given
      organization1 = AccountsFixtures.organization_fixture()
      organization2 = AccountsFixtures.organization_fixture()
      account1 = Accounts.get_account_from_organization(organization1)
      account2 = Accounts.get_account_from_organization(organization2)
      ProjectsFixtures.project_fixture(account_id: account1.id, name: "shared-name")
      ProjectsFixtures.project_fixture(account_id: account2.id, name: "shared-name")

      # When
      result =
        Projects.get_projects_by_handles_for_account(account1, ["shared-name", "other-project"])

      # Then
      assert {:error, :not_found, "other-project"} = result
    end
  end

  describe "projects_by_full_handles/1" do
    test "returns a map of full_handle to project for multiple projects" do
      # Given
      organization1 = AccountsFixtures.organization_fixture()
      organization2 = AccountsFixtures.organization_fixture()
      account1 = Accounts.get_account_from_organization(organization1)
      account2 = Accounts.get_account_from_organization(organization2)

      project1 = ProjectsFixtures.project_fixture(account_id: account1.id, name: "project1")
      project2 = ProjectsFixtures.project_fixture(account_id: account1.id, name: "project2")
      project3 = ProjectsFixtures.project_fixture(account_id: account2.id, name: "project3")

      full_handles = [
        "#{account1.name}/project1",
        "#{account1.name}/project2",
        "#{account2.name}/project3"
      ]

      # When
      got = Projects.projects_by_full_handles(full_handles)

      # Then
      assert map_size(got) == 3
      assert got["#{account1.name}/project1"].id == project1.id
      assert got["#{account1.name}/project2"].id == project2.id
      assert got["#{account2.name}/project3"].id == project3.id
    end

    test "returns empty map when no full handles provided" do
      # When
      got = Projects.projects_by_full_handles([])

      # Then
      assert got == %{}
    end

    test "excludes non-existent projects from result" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id, name: "existing-project")

      full_handles = [
        "#{account.name}/existing-project",
        "#{account.name}/non-existent-project",
        "non-existent-account/some-project"
      ]

      # When
      got = Projects.projects_by_full_handles(full_handles)

      # Then
      assert map_size(got) == 1
      assert got["#{account.name}/existing-project"].id == project.id
      refute Map.has_key?(got, "#{account.name}/non-existent-project")
      refute Map.has_key?(got, "non-existent-account/some-project")
    end

    test "handles duplicate full handles in input" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      full_handles = [
        "#{account.name}/#{project.name}",
        "#{account.name}/#{project.name}",
        "#{account.name}/#{project.name}"
      ]

      # When
      got = Projects.projects_by_full_handles(full_handles)

      # Then
      assert map_size(got) == 1
      assert got["#{account.name}/#{project.name}"].id == project.id
    end

    test "handles malformed full handles gracefully" do
      # Given
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      full_handles = [
        "#{account.name}/#{project.name}",
        "invalid-handle",
        "too/many/parts",
        ""
      ]

      # When
      got = Projects.projects_by_full_handles(full_handles)

      # Then
      assert map_size(got) == 1
      assert got["#{account.name}/#{project.name}"].id == project.id
    end
  end

  describe "get_project_tokens/1" do
    test "returns project's tokens" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, token_one} =
        project
        |> Projects.create_project_token()
        |> Projects.get_project_token()

      {:ok, token_two} =
        project
        |> Projects.create_project_token()
        |> Projects.get_project_token()

      _token_three = Projects.create_project_token(ProjectsFixtures.project_fixture())

      # When
      got = Projects.get_project_tokens(project)

      # Then
      assert Enum.sort_by(got, & &1.id) == Enum.sort_by([token_one, token_two], & &1.id)
    end

    test "returns empty array if there are no project's tokens" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      got = Projects.get_project_tokens(project)

      # Then
      assert [] == got
    end
  end

  describe "get_project_token/1" do
    test "returns project token" do
      # Given
      project = ProjectsFixtures.project_fixture()

      token = Projects.create_project_token(project)

      # When
      {:ok, got} = Projects.get_project_token(token)

      # Then
      [_audience, token_id, _token_hash] = String.split(token, "_")
      assert got.id == token_id
    end

    test "returns invalid if the token is invalid" do
      # When
      got = Projects.get_project_token("invalid-token")

      # Then
      assert {:error, :invalid_token} == got
    end

    test "returns not found if the token does not exist" do
      # When
      got = Projects.get_project_token("tuist_0fcc7a05-4f0d-490d-8545-1fe3171a2880_some-hash")

      # Then
      assert {:error, :not_found} == got
    end
  end

  describe "get_project_by_full_token/1" do
    test "returns project with a token" do
      # Given
      project = ProjectsFixtures.project_fixture()
      token = Projects.create_project_token(project)

      # When
      got = Projects.get_project_by_full_token(token)

      # Then
      assert got == project
    end

    test "returns project with a legacy token" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      got = Projects.get_project_by_full_token(project.token)

      # Then
      assert got == project
    end

    test "returns nil when the token does not exist" do
      # When
      got = Projects.get_project_by_full_token("some-non-existing-token")

      # Then
      assert got == nil
    end
  end

  describe "get_project_token_by_id/2" do
    test "returns project token" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, token} =
        project
        |> Projects.create_project_token()
        |> Projects.get_project_token()

      # When
      got = Projects.get_project_token_by_id(project, token.id)

      # Then
      assert got == token
    end

    test "returns nil if the token does not exist" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      got = Projects.get_project_token_by_id(project, "01909854-f9d1-7f9d-8956-b59155b0d8cc")

      # Then
      assert got == nil
    end
  end

  describe "create_project_token/1" do
    test "creates project token" do
      # Given
      project = ProjectsFixtures.project_fixture()

      expect(Base64, :encode, fn _ -> "generated-hash" end)

      # When
      got = Projects.create_project_token(project)

      # Then
      %{id: token_id} = Repo.one(ProjectToken)
      assert "tuist_#{token_id}_generated-hash" == got
    end
  end

  describe "revoke_project_token/1" do
    test "revokes project token" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, token} =
        project
        |> Projects.create_project_token()
        |> Projects.get_project_token()

      # When
      Projects.revoke_project_token(token)

      # Then
      assert [] == Projects.get_project_tokens(project)
    end
  end

  describe "legacy_token?/1" do
    test "returns true if the token is a legacy token" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      got = Projects.legacy_token?(project.token)

      # Then
      assert got == true
    end

    test "returns false if the token is not a legacy token" do
      # Given
      project = ProjectsFixtures.project_fixture()
      token = Projects.create_project_token(project)

      # When
      got = Projects.legacy_token?(token)

      # Then
      assert got == false
    end
  end

  describe "get_repository_url/1" do
    test "returns the repository URL" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            provider: :github,
            repository_full_handle: "tuist/tuist"
          ]
        )

      # When
      got = Projects.get_repository_url(project)

      # Then
      assert got == "https://github.com/tuist/tuist"
    end

    test "returns nil if the project does not have a vcs" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      got = Projects.get_repository_url(project)

      # Then
      assert got == nil
    end
  end

  describe "platforms/1" do
    test "returns the platforms for a project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "App",
        supported_platforms: [:ios]
      )

      # Then
      assert Projects.platforms(project) == [:ios]
    end
  end

  describe "platforms/2" do
    test "returns all platforms when device_platforms_only? is false (default)" do
      # Given
      project = ProjectsFixtures.project_fixture()

      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "App",
        supported_platforms: [:ios, :ios_simulator, :tvos, :tvos_simulator]
      )

      # When
      platforms_with_simulators = Projects.platforms(project, device_platforms_only?: false)
      platforms_default = Projects.platforms(project)

      # Then
      assert Enum.sort(platforms_with_simulators) == [:ios, :ios_simulator, :tvos, :tvos_simulator]
      assert Enum.sort(platforms_default) == [:ios, :ios_simulator, :tvos, :tvos_simulator]
    end

    test "maps simulators to devices when device_platforms_only? is true" do
      # Given
      project = ProjectsFixtures.project_fixture()

      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "App",
        supported_platforms: [
          :ios,
          :ios_simulator,
          :tvos,
          :tvos_simulator,
          :watchos,
          :watchos_simulator,
          :visionos,
          :visionos_simulator,
          :macos
        ]
      )

      # When
      platforms_device_only = Projects.platforms(project, device_platforms_only?: true)

      # Then
      assert Enum.sort(platforms_device_only) == [:ios, :macos, :tvos, :visionos, :watchos]
    end

    test "returns empty list when project has no platforms" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      platforms_with_simulators = Projects.platforms(project, device_platforms_only?: false)
      platforms_device_only = Projects.platforms(project, device_platforms_only?: true)

      # Then
      assert platforms_with_simulators == []
      assert platforms_device_only == []
    end

    test "maps simulator platforms to device platforms when project has only simulators" do
      # Given
      project = ProjectsFixtures.project_fixture()

      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "App",
        supported_platforms: [:ios_simulator, :tvos_simulator, :watchos_simulator, :visionos_simulator]
      )

      # When
      platforms_with_simulators = Projects.platforms(project, device_platforms_only?: false)
      platforms_device_only = Projects.platforms(project, device_platforms_only?: true)

      # Then
      assert Enum.sort(platforms_with_simulators) == [
               :ios_simulator,
               :tvos_simulator,
               :visionos_simulator,
               :watchos_simulator
             ]

      assert Enum.sort(platforms_device_only) == [:ios, :tvos, :visionos, :watchos]
    end

    test "returns device platforms unchanged when project has only device platforms" do
      # Given
      project = ProjectsFixtures.project_fixture()

      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "App",
        supported_platforms: [:ios, :tvos, :watchos, :visionos, :macos]
      )

      # When
      platforms_with_simulators = Projects.platforms(project, device_platforms_only?: false)
      platforms_device_only = Projects.platforms(project, device_platforms_only?: true)

      # Then
      assert Enum.sort(platforms_with_simulators) == [:ios, :macos, :tvos, :visionos, :watchos]
      assert Enum.sort(platforms_device_only) == [:ios, :macos, :tvos, :visionos, :watchos]
    end

    test "handles multiple previews with different platforms" do
      # Given
      project = ProjectsFixtures.project_fixture()

      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "App iOS",
        supported_platforms: [:ios, :ios_simulator]
      )

      AppBuildsFixtures.preview_fixture(
        project: project,
        display_name: "App tvOS",
        supported_platforms: [:tvos, :tvos_simulator]
      )

      # When
      platforms_with_simulators = Projects.platforms(project, device_platforms_only?: false)
      platforms_device_only = Projects.platforms(project, device_platforms_only?: true)

      # Then
      assert Enum.sort(platforms_with_simulators) == [:ios, :ios_simulator, :tvos, :tvos_simulator]
      assert Enum.sort(platforms_device_only) == [:ios, :tvos]
    end
  end

  describe "list_sorted_with_interaction_data/1" do
    test "sorts projects with interactions first, by most recent interaction" do
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)

      # Create projects
      project_a = ProjectsFixtures.project_fixture(name: "project-a", account_id: account.id)
      project_b = ProjectsFixtures.project_fixture(name: "project-b", account_id: account.id)
      project_c = ProjectsFixtures.project_fixture(name: "project-c", account_id: account.id)

      # Add interactions with different ran_at times
      CommandEventsFixtures.command_event_fixture(
        project_id: project_a.id,
        # oldest interaction
        ran_at: ~N[2025-06-05 10:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project_b.id,
        # newest interaction
        ran_at: ~N[2025-06-05 15:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project_c.id,
        # middle interaction
        ran_at: ~N[2025-06-05 12:00:00]
      )

      projects = [project_a, project_b, project_c]
      sorted_projects = Projects.list_sorted_with_interaction_data(projects)
      project_names = Enum.map(sorted_projects, & &1.name)

      # Should be sorted by most recent interaction first: B (15:00), C (12:00), A (10:00)
      assert project_names == ["project-b", "project-c", "project-a"]
    end

    test "sorts projects without interactions by creation date (newest first)" do
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)

      # Create projects at different times (no interactions)
      old_project =
        ProjectsFixtures.project_fixture(
          name: "old-project",
          account_id: account.id,
          created_at: ~N[2025-01-01 10:00:00]
        )

      recent_project =
        ProjectsFixtures.project_fixture(
          name: "recent-project",
          account_id: account.id,
          created_at: ~N[2025-06-01 10:00:00]
        )

      projects = [old_project, recent_project]
      sorted_projects = Projects.list_sorted_with_interaction_data(projects)
      project_names = Enum.map(sorted_projects, & &1.name)

      # Should be sorted by creation date (newest first)
      assert project_names == ["recent-project", "old-project"]
    end

    test "places projects with interactions before projects without interactions" do
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)

      # Create a recently created project (no interactions)
      recent_no_interaction =
        ProjectsFixtures.project_fixture(
          name: "recent-no-interaction",
          account_id: account.id,
          created_at: ~N[2025-06-05 10:00:00]
        )

      # Create an old project with an old interaction
      old_with_interaction =
        ProjectsFixtures.project_fixture(
          name: "old-with-interaction",
          account_id: account.id,
          created_at: ~N[2025-01-01 10:00:00]
        )

      # Add an old interaction to the old project
      CommandEventsFixtures.command_event_fixture(
        project_id: old_with_interaction.id,
        # very old interaction
        ran_at: ~N[2025-01-02 10:00:00]
      )

      projects = [recent_no_interaction, old_with_interaction]
      sorted_projects = Projects.list_sorted_with_interaction_data(projects)
      project_names = Enum.map(sorted_projects, & &1.name)

      # Project with interaction (even old) should appear before project without interaction (even recent)
      assert project_names == ["old-with-interaction", "recent-no-interaction"]
    end

    test "handles empty project list" do
      assert Projects.list_sorted_with_interaction_data([]) == []
    end

    test "uses most recent interaction for projects with multiple command events" do
      organization = AccountsFixtures.organization_fixture()
      account = Accounts.get_account_from_organization(organization)

      project_a = ProjectsFixtures.project_fixture(name: "project-a", account_id: account.id)
      project_b = ProjectsFixtures.project_fixture(name: "project-b", account_id: account.id)

      # Project A: old and recent interactions - most recent should be used for sorting
      CommandEventsFixtures.command_event_fixture(
        project_id: project_a.id,
        # old interaction
        ran_at: ~N[2025-06-01 10:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project_a.id,
        # most recent interaction
        ran_at: ~N[2025-06-05 15:00:00]
      )

      # Project B: single interaction in between
      CommandEventsFixtures.command_event_fixture(
        project_id: project_b.id,
        ran_at: ~N[2025-06-05 12:00:00]
      )

      projects = [project_a, project_b]
      sorted_projects = Projects.list_sorted_with_interaction_data(projects)
      project_names = Enum.map(sorted_projects, & &1.name)

      # Project A should come first (most recent interaction at 15:00)
      # Project B should come second (interaction at 12:00)
      assert project_names == ["project-a", "project-b"]
    end
  end

  describe "get_recent_projects_for_account/2" do
    test "returns the most recently interacted projects for an account" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      # Create projects
      project1 = ProjectsFixtures.project_fixture(account_id: account.id, name: "project-1")
      project2 = ProjectsFixtures.project_fixture(account_id: account.id, name: "project-2")
      project3 = ProjectsFixtures.project_fixture(account_id: account.id, name: "project-3")
      _project4 = ProjectsFixtures.project_fixture(account_id: account.id, name: "project-4")

      # Add interactions with different timestamps
      CommandEventsFixtures.command_event_fixture(
        project_id: project1.id,
        ran_at: ~N[2025-06-05 10:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project2.id,
        ran_at: ~N[2025-06-05 14:00:00]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project3.id,
        ran_at: ~N[2025-06-05 12:00:00]
      )

      # project4 has no interactions

      # When
      recent_projects = Projects.get_recent_projects_for_account(account, 3)

      # Then
      assert length(recent_projects) == 3
      project_names = Enum.map(recent_projects, & &1.name)
      # Should be ordered by most recent interaction
      assert project_names == ["project-2", "project-3", "project-1"]
    end

    test "respects the limit parameter" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      # Create 5 projects with interactions
      for i <- 1..5 do
        project = ProjectsFixtures.project_fixture(account_id: account.id, name: "project-#{i}")

        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          ran_at: NaiveDateTime.add(~N[2025-06-05 10:00:00], i * 3600)
        )
      end

      # When
      recent_projects = Projects.get_recent_projects_for_account(account, 2)

      # Then
      assert length(recent_projects) == 2
    end

    test "only returns projects with interactions" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      # Create projects
      project_with_interaction = ProjectsFixtures.project_fixture(account_id: account.id, name: "with-interaction")
      _project_without_interaction = ProjectsFixtures.project_fixture(account_id: account.id, name: "without-interaction")

      # Add interaction only to one project
      CommandEventsFixtures.command_event_fixture(
        project_id: project_with_interaction.id,
        ran_at: ~N[2025-06-05 10:00:00]
      )

      # When
      recent_projects = Projects.get_recent_projects_for_account(account)

      # Then
      assert length(recent_projects) == 1
      assert hd(recent_projects).name == "with-interaction"
    end

    test "includes previews in preload" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      project = ProjectsFixtures.project_fixture(account_id: account.id)
      AppBuildsFixtures.preview_fixture(project: project)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        ran_at: ~N[2025-06-05 10:00:00]
      )

      # When
      recent_projects = Projects.get_recent_projects_for_account(account, 1)

      # Then
      project_with_previews = hd(recent_projects)
      assert Ecto.assoc_loaded?(project_with_previews.previews)
      assert length(project_with_previews.previews) == 1
    end

    test "returns empty list when account has no projects with interactions" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      # Create project without interaction
      ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      recent_projects = Projects.get_recent_projects_for_account(account)

      # Then
      assert recent_projects == []
    end
  end

  describe "projects_by_vcs_repository_full_handle/1" do
    test "returns empty list when no projects found" do
      # Given
      vcs_handle = "nonexistent/project"

      # When
      projects = Projects.projects_by_vcs_repository_full_handle(vcs_handle)

      # Then
      assert [] == projects
    end

    test "returns single project when one project connected to repository" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      vcs_handle = "tuist/tuist"

      project =
        ProjectsFixtures.project_fixture(
          account_id: account.id,
          vcs_connection: [
            repository_full_handle: vcs_handle,
            provider: :github
          ]
        )

      # When
      projects = Projects.projects_by_vcs_repository_full_handle(vcs_handle)

      # Then
      assert length(projects) == 1
      assert List.first(projects).id == project.id
    end

    test "returns multiple projects for monorepo" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      vcs_handle = "tuist/monorepo"

      project_one =
        ProjectsFixtures.project_fixture(
          name: "mobile-app",
          account_id: account.id,
          vcs_connection: [
            repository_full_handle: vcs_handle,
            provider: :github
          ]
        )

      project_two =
        ProjectsFixtures.project_fixture(
          name: "admin-panel",
          account_id: account.id,
          vcs_connection: [
            repository_full_handle: vcs_handle,
            provider: :github
          ]
        )

      # When
      projects = Projects.projects_by_vcs_repository_full_handle(vcs_handle)

      # Then
      assert projects |> Enum.map(& &1.id) |> Enum.sort() == [project_one.id, project_two.id]
    end

    test "returns projects with preloaded associations" do
      # Given
      organization = AccountsFixtures.organization_fixture(name: "test-org")
      account = Accounts.get_account_from_organization(organization)
      vcs_handle = "test-org/test-project"

      project =
        ProjectsFixtures.project_fixture(
          account_id: account.id,
          vcs_connection: [
            repository_full_handle: vcs_handle,
            provider: :github
          ]
        )

      # When
      [got_project] = Projects.projects_by_vcs_repository_full_handle(vcs_handle, preload: [:account])

      # Then
      assert got_project.id == project.id
    end
  end

  describe "project_by_name_and_vcs_repository_full_handle/2" do
    test "returns project when found" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      vcs_handle = "tuist/monorepo"
      project_name = "mobile-app"

      project =
        ProjectsFixtures.project_fixture(
          name: project_name,
          account_id: account.id,
          vcs_connection: [
            repository_full_handle: vcs_handle,
            provider: :github
          ]
        )

      # When
      {:ok, got_project} = Projects.project_by_name_and_vcs_repository_full_handle(project_name, vcs_handle)

      # Then
      assert got_project.id == project.id
    end

    test "returns error when project not found" do
      # Given
      vcs_handle = "tuist/monorepo"
      project_name = "nonexistent"

      # When
      result = Projects.project_by_name_and_vcs_repository_full_handle(project_name, vcs_handle)

      # Then
      assert {:error, :not_found} == result
    end

    test "returns correct project when multiple projects in monorepo" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      vcs_handle = "tuist/monorepo"

      project_one =
        ProjectsFixtures.project_fixture(
          name: "mobile-app",
          account_id: account.id,
          vcs_connection: [
            repository_full_handle: vcs_handle,
            provider: :github
          ]
        )

      ProjectsFixtures.project_fixture(
        name: "admin-panel",
        account_id: account.id,
        vcs_connection: [
          repository_full_handle: vcs_handle,
          provider: :github
        ]
      )

      # When
      {:ok, got_project} = Projects.project_by_name_and_vcs_repository_full_handle("mobile-app", vcs_handle)

      # Then
      assert got_project.id == project_one.id
    end
  end

  describe "create_vcs_connection/1" do
    test "creates a new VCS connection" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Repo.preload(project, :account).account

      {:ok, github_app_installation} =
        VCS.create_github_app_installation(%{
          account_id: account.id,
          installation_id: "test-installation-123"
        })

      attrs = %{
        project_id: project.id,
        provider: :github,
        repository_full_handle: "tuist/tuist",
        github_app_installation_id: github_app_installation.id
      }

      # When
      {:ok, vcs_connection} = Projects.create_vcs_connection(attrs)

      # Then
      assert vcs_connection.project_id == project.id
      assert vcs_connection.provider == :github
      assert vcs_connection.repository_full_handle == "tuist/tuist"
      assert vcs_connection.github_app_installation_id == github_app_installation.id
    end

    test "returns error with invalid attrs" do
      # Given
      attrs = %{
        provider: :github,
        repository_full_handle: "tuist/tuist"
      }

      # When
      {:error, changeset} = Projects.create_vcs_connection(attrs)

      # Then
      assert %{project_id: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "delete_vcs_connection/1" do
    test "deletes a VCS connection" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Repo.preload(project, :account).account

      {:ok, github_app_installation} =
        VCS.create_github_app_installation(%{
          account_id: account.id,
          installation_id: "test-installation-456"
        })

      {:ok, vcs_connection} =
        Projects.create_vcs_connection(%{
          project_id: project.id,
          provider: :github,
          repository_full_handle: "tuist/tuist",
          github_app_installation_id: github_app_installation.id
        })

      # When
      {:ok, _} = Projects.delete_vcs_connection(vcs_connection)

      # Then
      assert Projects.get_vcs_connection(vcs_connection.id) == {:error, :not_found}
    end
  end

  describe "get_vcs_connection/1" do
    test "returns VCS connection when it exists" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = Repo.preload(project, :account).account

      {:ok, github_app_installation} =
        VCS.create_github_app_installation(%{
          account_id: account.id,
          installation_id: "test-installation-789"
        })

      {:ok, vcs_connection} =
        Projects.create_vcs_connection(%{
          project_id: project.id,
          provider: :github,
          repository_full_handle: "tuist/tuist",
          github_app_installation_id: github_app_installation.id
        })

      # When
      {:ok, got} = Projects.get_vcs_connection(vcs_connection.id)

      # Then
      assert got.id == vcs_connection.id
      assert got.repository_full_handle == "tuist/tuist"
    end

    test "returns error when VCS connection does not exist" do
      # When
      got = Projects.get_vcs_connection("01909854-f9d1-7f9d-8956-b59155b0d8cc")

      # Then
      assert got == {:error, :not_found}
    end
  end
end
