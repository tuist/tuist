defmodule Tuist.VCSTest do
  use ExUnit.Case, async: false
  use TuistTestSupport.Cases.StubCase, billing: true
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.GitHub
  alias Tuist.VCS
  alias Tuist.VCS.Comment
  alias Tuist.VCS.Repositories.Permission
  alias Tuist.VCS.Repositories.Repository
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.BundlesFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  @default_headers [
    {"Accept", "application/vnd.github.v3+json"},
    {"Authorization", "token github_token"}
  ]

  setup do
    stub(GitHub.App, :get_app_installation_token_for_repository, fn "tuist/tuist" ->
      {:ok, %{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
    end)

    stub(Environment, :github_app_client_id, fn -> "client_id" end)

    :ok
  end

  describe "get_user_permission/1" do
    test "returns user permission when admin" do
      # Given
      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :github,
          uid: 123,
          info: %{
            email: "tuist@tuist.dev"
          }
        })

      expect(GitHub.Client, :get_user_by_id, fn %{
                                                  id: "123",
                                                  repository_full_handle: "tuist/tuist"
                                                } ->
        {:ok, %VCS.User{username: "tuist"}}
      end)

      expect(GitHub.Client, :get_user_permission, fn %{
                                                       repository_full_handle: "tuist/tuist",
                                                       username: "tuist"
                                                     } ->
        {:ok, %Permission{permission: "admin"}}
      end)

      # When
      got =
        VCS.get_user_permission(%{
          user: user,
          repository: %Repository{
            provider: :github,
            full_handle: "tuist/tuist",
            default_branch: "main"
          }
        })

      # Then
      assert got == {:ok, %Permission{permission: "admin"}}
    end
  end

  describe "connected/1" do
    test "returns true when connected" do
      # Given
      stub(Environment, :github_app_configured?, fn -> true end)

      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      # When
      got = VCS.connected?(%{project: project, repository_full_handle: "tuist/tuist"})

      # Then
      assert got == true
    end

    test "returns true when connected but casing differs" do
      # Given
      stub(Environment, :github_app_configured?, fn -> true end)

      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      # When
      got = VCS.connected?(%{project: project, repository_full_handle: "tuist/Tuist"})

      # Then
      assert got == true
    end

    test "returns false when the GitHub app is not configured" do
      # Given
      stub(Environment, :github_app_configured?, fn -> false end)

      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      # When
      got = VCS.connected?(%{project: project, repository_full_handle: "tuist/tuist"})

      # Then
      assert got == false
    end

    test "returns false when the vcs_repository_full_handle is nil" do
      # Given
      stub(Environment, :github_app_configured?, fn -> false end)

      project =
        ProjectsFixtures.project_fixture(vcs_repository_full_handle: nil)

      # When
      got = VCS.connected?(%{project: project, repository_full_handle: "tuist/tuist"})

      # Then
      assert got == false
    end

    test "returns false when the connected repositor full handles' do not match" do
      # Given
      stub(Environment, :github_app_configured?, fn -> false end)

      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      # When
      got = VCS.connected?(%{project: project, repository_full_handle: "tuist/tuist-different"})

      # Then
      assert got == false
    end
  end

  describe "get_repository_from_repository_url/1" do
    test "returns repository when it exists" do
      # Given
      repository_url = "https://github.com/tuist/tuist"

      expect(GitHub.Client, :get_repository, fn "tuist/tuist" ->
        {:ok,
         %Repository{
           provider: :github,
           full_handle: "tuist/tuist",
           default_branch: "main"
         }}
      end)

      # When
      got =
        VCS.get_repository_from_repository_url(repository_url)

      # Then
      assert got ==
               {:ok,
                %Repository{
                  provider: :github,
                  full_handle: "tuist/tuist",
                  default_branch: "main"
                }}
    end

    test "returns repository with username" do
      # Given
      repository_url = "https://tuist@github.com/tuist/tuist.git"

      expect(GitHub.Client, :get_repository, fn "tuist/tuist" ->
        {:ok,
         %Repository{
           provider: :github,
           full_handle: "tuist/tuist",
           default_branch: "main"
         }}
      end)

      # When
      got =
        VCS.get_repository_from_repository_url(repository_url)

      # Then
      assert got ==
               {:ok,
                %Repository{
                  provider: :github,
                  full_handle: "tuist/tuist",
                  default_branch: "main"
                }}
    end

    test "returns repository with .git suffix" do
      # Given
      repository_url = "https://github.com/tuist/tuist.git"

      expect(GitHub.Client, :get_repository, fn "tuist/tuist" ->
        {:ok,
         %Repository{
           provider: :github,
           full_handle: "tuist/tuist",
           default_branch: "main"
         }}
      end)

      # When
      got =
        VCS.get_repository_from_repository_url(repository_url)

      # Then
      assert got ==
               {:ok,
                %Repository{
                  provider: :github,
                  full_handle: "tuist/tuist",
                  default_branch: "main"
                }}
    end

    test "returns repository with trailing slash" do
      # Given
      repository_url = "https://github.com/tuist/tuist/"

      expect(GitHub.Client, :get_repository, fn "tuist/tuist" ->
        {:ok,
         %Repository{
           provider: :github,
           full_handle: "tuist/tuist",
           default_branch: "main"
         }}
      end)

      # When
      got =
        VCS.get_repository_from_repository_url(repository_url)

      # Then
      assert got ==
               {:ok,
                %Repository{
                  provider: :github,
                  full_handle: "tuist/tuist",
                  default_branch: "main"
                }}
    end
  end

  describe "post_vcs_pull_request_comment/1" do
    @git_ref "refs/pull/1/merge"
    @git_remote_url_origin "https://github.com/tuist/tuist"
    @git_commit_sha "1234567890"

    setup do
      stub(Environment, :github_app_client_id, fn -> "client_id" end)
      stub(Environment, :github_app_configured?, fn -> true end)
      :ok
    end

    test "creates a comment with a full report" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      preview_one =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_ref: @git_ref,
          git_commit_sha: @git_commit_sha,
          inserted_at: ~N[2024-04-30 03:00:00]
        )

      _app_build_one =
        AppBuildsFixtures.app_build_fixture(
          preview: preview_one,
          project: project,
          display_name: "App"
        )

      preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_ref: @git_ref,
          git_commit_sha: @git_commit_sha,
          inserted_at: ~N[2024-04-30 02:00:00]
        )

      _app_build_two =
        AppBuildsFixtures.app_build_fixture(
          preview: preview_two,
          project: project,
          display_name: "App"
        )

      preview_three =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "WatchApp",
          git_ref: @git_ref,
          git_commit_sha: @git_commit_sha,
          inserted_at: ~N[2024-04-30 01:00:00]
        )

      _app_build_three =
        AppBuildsFixtures.app_build_fixture(
          preview: preview_three,
          project: project,
          display_name: "WatchApp"
        )

      test_command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "test",
          git_ref: @git_ref,
          project_id: project.id,
          command_arguments: ["test"],
          git_commit_sha: @git_commit_sha,
          created_at: ~N[2024-04-30 03:00:00]
        )

      test_command_event_two =
        CommandEventsFixtures.command_event_fixture(
          name: "test",
          git_ref: @git_ref,
          project_id: project.id,
          command_arguments: ["test App"],
          git_commit_sha: @git_commit_sha,
          created_at: ~N[2024-04-30 04:00:00],
          cacheable_targets: ["A", "B", "C", "D"],
          local_cache_target_hits: ["A"],
          remote_cache_target_hits: ["C"],
          test_targets: ["ATests", "BTests", "CTests", "DTests"],
          local_test_target_hits: ["ATests", "BTests"],
          remote_test_target_hits: ["CTests"],
          status: :failure
        )

      stub(Req, :get, fn _opts ->
        {:ok, %Req.Response{status: 200, body: []}}
      end)

      commit_link = "[123456789](#{@git_remote_url_origin}/commit/#{@git_commit_sha})"

      expected_body =
        """
        ### 🛠️ Tuist Run Report 🛠️

        #### Previews 📦

        | App | Commit |
        | - | - |
        | [App](https://tuist.dev/previews/#{preview_one.id}) | #{commit_link} |
        | [WatchApp](https://tuist.dev/previews/#{preview_three.id}) | #{commit_link} |


        #### Tests 🧪

        | Command | Status | Cache hit rate | Tests | Skipped | Ran | Commit |
        |:-:|:-:|:-:|:-:|:-:|:-:|:-:|
        | [test](https://tuist.dev/runs/#{test_command_event_one.id}) | ✅ | 0 % | 0 | 0 | 0 | #{commit_link} |
        | [test App](https://tuist.dev/runs/#{test_command_event_two.id}) | ❌ | 50 % | 4 | 3 | 1 | #{commit_link} |

        """

      stub(Req, :post, fn opts ->
        assert opts[:finch] == Tuist.Finch
        assert opts[:headers] == @default_headers
        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/issues/1/comments"
        assert opts[:json] == %{body: expected_body}

        {:ok, %Req.Response{status: 200, body: %{}}}
      end)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.dev/previews/#{preview.id}" end,
        preview_qr_code_url: fn %{preview: preview} ->
          "https://tuist.dev/previews/#{preview.id}/qr-code.svg"
        end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.dev/runs/#{command_event.id}"
        end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "creates a comment with ipa previews" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      preview_one =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_ref: @git_ref,
          git_commit_sha: @git_commit_sha,
          inserted_at: ~N[2024-04-30 03:00:00]
        )

      # Create an IPA app build for the group
      _app_build_one =
        AppBuildsFixtures.app_build_fixture(
          preview: preview_one,
          project: project,
          display_name: "App",
          type: :ipa
        )

      preview_two =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "WatchApp",
          git_ref: @git_ref,
          git_commit_sha: @git_commit_sha,
          inserted_at: ~N[2024-04-30 01:00:00]
        )

      _app_build_two =
        AppBuildsFixtures.app_build_fixture(
          preview: preview_two,
          project: project,
          display_name: "WatchApp"
        )

      stub(Req, :get, fn _opts ->
        {:ok, %Req.Response{status: 200, body: []}}
      end)

      commit_link = "[123456789](#{@git_remote_url_origin}/commit/#{@git_commit_sha})"

      expected_body =
        """
        ### 🛠️ Tuist Run Report 🛠️

        #### Previews 📦

        | App | Commit | Open on device |
        | - | - | - |
        | [App](https://tuist.dev/previews/#{preview_one.id}) | #{commit_link} | <img width=100px src="https://tuist.dev/#{project.name}/previews/#{preview_one.id}/qr-code.svg" /> |
        | [WatchApp](https://tuist.dev/previews/#{preview_two.id}) | #{commit_link} | |

        """

      expect(Req, :post, fn opts ->
        assert opts[:finch] == Tuist.Finch
        assert opts[:headers] == @default_headers
        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/issues/1/comments"
        assert opts[:json] == %{body: expected_body}

        {:ok, %Req.Response{status: 200, body: %{}}}
      end)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.dev/previews/#{preview.id}" end,
        preview_qr_code_url: fn %{preview: preview, project: project} ->
          "https://tuist.dev/#{project.name}/previews/#{preview.id}/qr-code.svg"
        end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.dev/runs/#{command_event.id}"
        end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "creates a comment when full handle and provider is the same but url is different" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_ref: @git_ref,
          git_commit_sha: @git_commit_sha,
          inserted_at: ~N[2024-04-30 03:00:00]
        )

      _app_build =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          project: project,
          display_name: "App"
        )

      expect(GitHub.Client, :get_comments, fn _ -> {:ok, []} end)

      expect(GitHub.Client, :create_comment, fn %{
                                                  repository_full_handle: "tuist/tuist",
                                                  issue_id: "1",
                                                  body: _
                                                } ->
        {:ok, %{}}
      end)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: "https://tuist@github.com/tuist/tuist",
        preview_url: fn %{preview: preview} -> "https://tuist.dev/previews/#{preview.id}" end,
        preview_qr_code_url: fn %{preview: preview} ->
          "https://tuist.dev/previews/#{preview.id}/qr-code.svg"
        end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.dev/runs/#{command_event.id}"
        end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "creates a comment when full handle and provider is the same and the origin is using SSH" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_ref: @git_ref,
          git_commit_sha: @git_commit_sha,
          inserted_at: ~N[2024-04-30 03:00:00]
        )

      _app_build =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          project: project,
          display_name: "App"
        )

      expect(GitHub.Client, :get_comments, fn _ -> {:ok, []} end)

      expect(GitHub.Client, :create_comment, fn %{
                                                  repository_full_handle: "tuist/tuist",
                                                  issue_id: "1",
                                                  body: _
                                                } ->
        {:ok, %{}}
      end)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: "git@github.com:tuist/tuist.git",
        preview_url: fn %{preview: preview} -> "https://tuist.dev/previews/#{preview.id}" end,
        preview_qr_code_url: fn %{preview: preview} ->
          "https://tuist.dev/previews/#{preview.id}/qr-code.svg"
        end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.dev/runs/#{command_event.id}"
        end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "updates a comment if one already exists" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_ref: @git_ref,
          git_commit_sha: "1234567890"
        )

      _app_build =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          project: project,
          display_name: "App"
        )

      expect(GitHub.Client, :get_comments, fn _ ->
        {:ok,
         [
           %Comment{
             id: 1,
             client_id: "client_id",
             body: "### 🛠️ Tuist Run Report 🛠️\n\nSome existing content"
           }
         ]}
      end)

      stub(GitHub.App, :get_app_installation_token_for_repository, fn "tuist/tuist" ->
        {:ok, %{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
      end)

      stub(Req, :patch, fn opts ->
        assert opts[:finch] == Tuist.Finch

        assert opts[:headers] == [
                 {"Accept", "application/vnd.github.v3+json"},
                 {"Authorization", "token github_token"}
               ]

        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/issues/comments/1"
        assert Map.has_key?(opts[:json], :body)

        {:ok, %Req.Response{status: 200, body: %{}}}
      end)

      reject(GitHub.Client, :create_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.dev/previews/#{preview.id}" end,
        preview_qr_code_url: fn %{preview: preview} ->
          "https://tuist.dev/previews/#{preview.id}/qr-code.svg"
        end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.dev/runs/#{command_event.id}"
        end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "does not create a comment when there is nothing to report" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      expect(GitHub.Client, :get_comments, fn _ -> {:ok, []} end)
      reject(GitHub.Client, :create_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.dev/previews/#{preview.id}" end,
        preview_qr_code_url: fn %{preview: preview} ->
          "https://tuist.dev/previews/#{preview.id}/qr-code.svg"
        end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.dev/runs/#{command_event.id}"
        end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "creates a new comment when existing comment has same client_id but is not a Tuist Run Report" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_ref: @git_ref,
          git_commit_sha: "1234567890"
        )

      _app_build =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          project: project,
          display_name: "App"
        )

      # Mock existing comment with same client_id but different content (not a Tuist Run Report)
      expect(GitHub.Client, :get_comments, fn _ ->
        {:ok,
         [
           %Comment{
             id: 1,
             client_id: "client_id",
             body: "This is a different comment from the Tuist bot"
           }
         ]}
      end)

      expect(GitHub.Client, :create_comment, fn %{
                                                  repository_full_handle: "tuist/tuist",
                                                  issue_id: "1",
                                                  body: body
                                                } ->
        assert String.starts_with?(body, "### 🛠️ Tuist Run Report 🛠️")
        {:ok, %{id: 2}}
      end)

      reject(GitHub.Client, :update_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.dev/previews/#{preview.id}" end,
        preview_qr_code_url: fn %{preview: preview} ->
          "https://tuist.dev/previews/#{preview.id}/qr-code.svg"
        end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.dev/runs/#{command_event.id}"
        end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "does not create a comment when the GitHub app is not configured" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      stub(Environment, :github_app_configured?, fn -> false end)
      reject(GitHub.Client, :get_comments, 1)
      reject(GitHub.Client, :create_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.dev/previews/#{preview.id}" end,
        preview_qr_code_url: fn %{preview: preview} ->
          "https://tuist.dev/previews/#{preview.id}/qr-code.svg"
        end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.dev/runs/#{command_event.id}"
        end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "does not create a comment when the git ref is not a pull request" do
      # Given
      project = ProjectsFixtures.project_fixture()

      reject(GitHub.Client, :get_comments, 1)
      reject(GitHub.Client, :create_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: "tags/1.0.0",
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.dev/previews/#{preview.id}" end,
        preview_qr_code_url: fn %{preview: preview} ->
          "https://tuist.dev/previews/#{preview.id}/qr-code.svg"
        end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.dev/runs/#{command_event.id}"
        end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "does not create a comment when the git ref is missing" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      reject(GitHub.Client, :get_comments, 1)
      reject(GitHub.Client, :create_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_ref: nil,
        git_commit_sha: @git_commit_sha,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.dev/previews/#{preview.id}" end,
        preview_qr_code_url: fn %{preview: preview} ->
          "https://tuist.dev/previews/#{preview.id}/qr-code.svg"
        end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.dev/runs/#{command_event.id}"
        end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "does not create a comment when the git remote url origin is missing" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      reject(GitHub.Client, :get_comments, 1)
      reject(GitHub.Client, :create_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_remote_url_origin: nil,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        preview_url: fn %{preview: preview} -> "https://tuist.dev/previews/#{preview.id}" end,
        preview_qr_code_url: fn %{preview: preview} ->
          "https://tuist.dev/previews/#{preview.id}/qr-code.svg"
        end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.dev/runs/#{command_event.id}"
        end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "does not create a comment when the git remote url origin has a different handle" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/different-handle",
          vcs_provider: :github
        )

      reject(GitHub.Client, :get_comments, 1)
      reject(GitHub.Client, :create_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_remote_url_origin: @git_remote_url_origin,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        preview_url: fn %{preview: preview} -> "https://tuist.dev/previews/#{preview.id}" end,
        preview_qr_code_url: fn %{preview: preview} ->
          "https://tuist.dev/previews/#{preview.id}/qr-code.svg"
        end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.dev/runs/#{command_event.id}"
        end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "creates a comment with bundles" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      BundlesFixtures.bundle_fixture(
        project: project,
        install_size: 2000,
        download_size: 2000,
        git_branch: "main",
        inserted_at: ~U[2024-01-01 03:00:00Z]
      )

      BundlesFixtures.bundle_fixture(
        project: project,
        install_size: 1000,
        download_size: 3000,
        git_branch: "feat/my-feature",
        inserted_at: ~U[2024-01-01 04:00:00Z]
      )

      bundle_ios_app =
        BundlesFixtures.bundle_fixture(
          project: project,
          install_size: 1000,
          download_size: 3000,
          git_ref: @git_ref,
          git_commit_sha: @git_commit_sha,
          inserted_at: ~U[2024-01-01 05:00:00Z]
        )

      stub(Req, :get, fn _opts ->
        {:ok, %Req.Response{status: 200, body: []}}
      end)

      commit_link = "[123456789](#{@git_remote_url_origin}/commit/#{@git_commit_sha})"

      expected_body =
        """
        ### 🛠️ Tuist Run Report 🛠️

        #### Bundles 🧰

        | Bundle | Commit | Install size | Download size |
        | - | - | - | - |
        | [App](https://tuist.dev/bundles/#{bundle_ios_app.id}) | #{commit_link} | <div align=\"center\">1.0 KB<br/>`Δ -1.0 KB (-50.00%)`</div> | <div align=\"center\">3.0 KB<br/>`Δ +1.0 KB (+50.00%)`</div> |

        """

      expect(Req, :post, fn opts ->
        assert opts[:finch] == Tuist.Finch
        assert opts[:headers] == @default_headers
        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/issues/1/comments"
        assert opts[:json] == %{body: expected_body}

        {:ok, %Req.Response{status: 200, body: %{}}}
      end)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        command_name: "bundle",
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn _ -> "" end,
        preview_qr_code_url: fn _ -> "" end,
        command_run_url: fn _ -> "" end,
        bundle_url: fn %{bundle: bundle} -> "https://tuist.dev/bundles/#{bundle.id}" end,
        build_url: fn _ -> "" end
      })
    end

    test "creates a comment with builds" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      {:ok, build_run} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          scheme: "MyApp",
          status: :success,
          duration: 45_000,
          category: :clean,
          xcode_version: "15.0",
          git_commit_sha: @git_commit_sha,
          git_ref: @git_ref
        )

      stub(Req, :get, fn _opts ->
        {:ok, %Req.Response{status: 200, body: []}}
      end)

      commit_link = "[123456789](#{@git_remote_url_origin}/commit/#{@git_commit_sha})"

      expected_body =
        """
        ### 🛠️ Tuist Run Report 🛠️

        #### Builds 🔨

        | Scheme | Status | Duration | Commit |
        |:-:|:-:|:-:|:-:|
        | [MyApp](https://tuist.dev/build-runs/#{build_run.id}) | ✅ | 45.0s | #{commit_link} |

        """

      expect(Req, :post, fn opts ->
        assert opts[:finch] == Tuist.Finch
        assert opts[:headers] == @default_headers
        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/issues/1/comments"
        assert opts[:json] == %{body: expected_body}

        {:ok, %Req.Response{status: 200, body: %{}}}
      end)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn _ -> "" end,
        preview_qr_code_url: fn _ -> "" end,
        command_run_url: fn _ -> "" end,
        bundle_url: fn _ -> "" end,
        build_url: fn %{build: build} -> "https://tuist.dev/build-runs/#{build.id}" end
      })
    end

    test "does not show size delta when there is no last bundle" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      bundle_ios_app =
        BundlesFixtures.bundle_fixture(
          project: project,
          install_size: 1000,
          download_size: 3000,
          git_ref: @git_ref,
          git_commit_sha: @git_commit_sha,
          inserted_at: ~U[2024-01-01 04:00:00Z]
        )

      stub(Req, :get, fn _opts ->
        {:ok, %Req.Response{status: 200, body: []}}
      end)

      commit_link = "[123456789](#{@git_remote_url_origin}/commit/#{@git_commit_sha})"

      expected_body =
        """
        ### 🛠️ Tuist Run Report 🛠️

        #### Bundles 🧰

        | Bundle | Commit | Install size | Download size |
        | - | - | - | - |
        | [App](https://tuist.dev/bundles/#{bundle_ios_app.id}) | #{commit_link} | <div align=\"center\">1.0 KB</div> | <div align=\"center\">3.0 KB</div> |

        """

      expect(Req, :post, fn opts ->
        assert opts[:finch] == Tuist.Finch
        assert opts[:headers] == @default_headers
        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/issues/1/comments"
        assert opts[:json] == %{body: expected_body}

        {:ok, %Req.Response{status: 200, body: %{}}}
      end)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn _ -> "" end,
        preview_qr_code_url: fn _ -> "" end,
        command_run_url: fn _ -> "" end,
        bundle_url: fn %{bundle: bundle} -> "https://tuist.dev/bundles/#{bundle.id}" end,
        build_url: fn _ -> "" end
      })
    end

    test "shows Unknown when download_size is nil" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      bundle_ios_app =
        BundlesFixtures.bundle_fixture(
          project: project,
          install_size: 1000,
          download_size: nil,
          git_ref: @git_ref,
          git_commit_sha: @git_commit_sha,
          inserted_at: ~U[2024-01-01 04:00:00Z]
        )

      stub(Req, :get, fn _opts ->
        {:ok, %Req.Response{status: 200, body: []}}
      end)

      commit_link = "[123456789](#{@git_remote_url_origin}/commit/#{@git_commit_sha})"

      expected_body =
        """
        ### 🛠️ Tuist Run Report 🛠️

        #### Bundles 🧰

        | Bundle | Commit | Install size | Download size |
        | - | - | - | - |
        | [App](https://tuist.dev/bundles/#{bundle_ios_app.id}) | #{commit_link} | <div align=\"center\">1.0 KB</div> | <div align=\"center\">Unknown</div> |

        """

      expect(Req, :post, fn opts ->
        assert opts[:finch] == Tuist.Finch
        assert opts[:headers] == @default_headers
        assert opts[:url] == "https://api.github.com/repos/tuist/tuist/issues/1/comments"
        assert opts[:json] == %{body: expected_body}

        {:ok, %Req.Response{status: 200, body: %{}}}
      end)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn _ -> "" end,
        preview_qr_code_url: fn _ -> "" end,
        command_run_url: fn _ -> "" end,
        bundle_url: fn %{bundle: bundle} -> "https://tuist.dev/bundles/#{bundle.id}" end,
        build_url: fn _ -> "" end
      })
    end
  end

  describe "create_comment/1" do
    setup do
      stub(Environment, :github_app_configured?, fn -> true end)
      :ok
    end

    test "successfully creates a comment for a pull request" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      expect(GitHub.Client, :create_comment, fn %{
                                                  repository_full_handle: "tuist/tuist",
                                                  issue_id: "123",
                                                  body: "This is a test comment"
                                                } ->
        {:ok, %Comment{id: 1, client_id: "client_id"}}
      end)

      # When
      result =
        VCS.create_comment(%{
          repository_full_handle: "tuist/tuist",
          git_ref: "refs/pull/123/merge",
          body: "This is a test comment",
          project: project
        })

      # Then
      assert {:ok, %Comment{id: 1, client_id: "client_id"}} == result
    end

    test "returns error when git ref is not a pull request" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      reject(GitHub.Client, :create_comment, 1)

      # When
      result =
        VCS.create_comment(%{
          repository_full_handle: "tuist/tuist",
          git_ref: "refs/heads/main",
          body: "This is a test comment",
          project: project
        })

      # Then
      assert {:error, :not_pull_request} == result
    end

    test "returns error when git ref is a tag" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      reject(GitHub.Client, :create_comment, 1)

      # When
      result =
        VCS.create_comment(%{
          repository_full_handle: "tuist/tuist",
          git_ref: "refs/tags/v1.0.0",
          body: "This is a test comment",
          project: project
        })

      # Then
      assert {:error, :not_pull_request} == result
    end

    test "returns error when repository is not connected" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "different/repo",
          vcs_provider: :github
        )

      reject(GitHub.Client, :create_comment, 1)

      # When
      result =
        VCS.create_comment(%{
          repository_full_handle: "tuist/tuist",
          git_ref: "refs/pull/123/merge",
          body: "This is a test comment",
          project: project
        })

      # Then
      assert {:error, :repository_not_connected} == result
    end

    test "returns error when GitHub app is not configured" do
      # Given
      stub(Environment, :github_app_configured?, fn -> false end)

      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      reject(GitHub.Client, :create_comment, 1)

      # When
      result =
        VCS.create_comment(%{
          repository_full_handle: "tuist/tuist",
          git_ref: "refs/pull/123/merge",
          body: "This is a test comment",
          project: project
        })

      # Then
      assert {:error, :repository_not_connected} == result
    end

    test "handles GitHub client errors" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      expect(GitHub.Client, :create_comment, fn %{
                                                  repository_full_handle: "tuist/tuist",
                                                  issue_id: "123",
                                                  body: "This is a test comment"
                                                } ->
        {:error, :forbidden}
      end)

      # When
      result =
        VCS.create_comment(%{
          repository_full_handle: "tuist/tuist",
          git_ref: "refs/pull/123/merge",
          body: "This is a test comment",
          project: project
        })

      # Then
      assert {:error, :forbidden} == result
    end
  end

  describe "update_comment/1" do
    setup do
      stub(Environment, :github_app_configured?, fn -> true end)
      :ok
    end

    test "successfully updates a comment when repository is connected" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      comment_params = %{
        repository_full_handle: "tuist/tuist",
        comment_id: "123456",
        body: "Updated comment body",
        project: project
      }

      expect(GitHub.Client, :update_comment, fn %{
                                                  repository_full_handle: "tuist/tuist",
                                                  comment_id: "123456",
                                                  body: "Updated comment body"
                                                } ->
        {:ok, %Comment{id: 123_456, client_id: "client_id"}}
      end)

      # When
      result = VCS.update_comment(comment_params)

      # Then
      assert {:ok, %Comment{id: 123_456, client_id: "client_id"}} = result
    end

    test "returns error when repository is not connected" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "different/repo",
          vcs_provider: :github
        )

      comment_params = %{
        repository_full_handle: "tuist/tuist",
        comment_id: "123456",
        body: "Updated comment body",
        project: project
      }

      reject(GitHub.Client, :update_comment, 1)

      # When
      result = VCS.update_comment(comment_params)

      # Then
      assert {:error, :repository_not_connected} = result
    end

    test "returns error when GitHub app is not configured" do
      # Given
      stub(Environment, :github_app_configured?, fn -> false end)

      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      comment_params = %{
        repository_full_handle: "tuist/tuist",
        comment_id: "123456",
        body: "Updated comment body",
        project: project
      }

      reject(GitHub.Client, :update_comment, 1)

      # When
      result = VCS.update_comment(comment_params)

      # Then
      assert {:error, :repository_not_connected} = result
    end

    test "handles GitHub client errors" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      comment_params = %{
        repository_full_handle: "tuist/tuist",
        comment_id: "123456",
        body: "Updated comment body",
        project: project
      }

      expect(GitHub.Client, :update_comment, fn %{
                                                  repository_full_handle: "tuist/tuist",
                                                  comment_id: "123456",
                                                  body: "Updated comment body"
                                                } ->
        {:error, :not_found}
      end)

      # When
      result = VCS.update_comment(comment_params)

      # Then
      assert {:error, :not_found} = result
    end

    test "works with different comment ID formats" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      comment_ids = ["123", "456789", "999"]

      for comment_id <- comment_ids do
        comment_params = %{
          repository_full_handle: "tuist/tuist",
          comment_id: comment_id,
          body: "Updated comment for ID #{comment_id}",
          project: project
        }

        expect(GitHub.Client, :update_comment, fn %{
                                                    repository_full_handle: "tuist/tuist",
                                                    comment_id: ^comment_id,
                                                    body: _
                                                  } ->
          {:ok, %Comment{id: String.to_integer(comment_id), client_id: "client_id"}}
        end)

        # When / Then
        result = VCS.update_comment(comment_params)
        assert {:ok, %Comment{}} = result
      end
    end
  end

  describe "enqueue_vcs_pull_request_comment/1" do
    test "enqueues VCS comment job with correct parameters" do
      # Given
      project = ProjectsFixtures.project_fixture()
      {:ok, build} = RunsFixtures.build_fixture(project_id: project.id)

      job_params = %{
        build_id: build.id,
        git_commit_sha: "abc123",
        git_ref: "refs/pull/123/head",
        git_remote_url_origin: "https://github.com/tuist/tuist",
        project_id: project.id,
        preview_url_template: "/{{account_name}}/{{project_name}}/previews/{{preview_id}}",
        preview_qr_code_url_template: "/{{account_name}}/{{project_name}}/previews/{{preview_id}}/qr-code.png",
        command_run_url_template: "/{{account_name}}/{{project_name}}/runs/{{command_event_id}}",
        bundle_url_template: "/{{account_name}}/{{project_name}}/bundles/{{bundle_id}}",
        build_url_template: "/{{account_name}}/{{project_name}}/builds/build-runs/{{build_id}}"
      }

      # When / Then
      Oban.Testing.with_testing_mode(:manual, fn ->
        result = VCS.enqueue_vcs_pull_request_comment(job_params)

        assert {:ok, %Oban.Job{}} = result

        assert_enqueued(
          worker: VCS.Workers.CommentWorker,
          args: %{
            "build_id" => build.id,
            "git_commit_sha" => "abc123",
            "git_ref" => "refs/pull/123/head",
            "git_remote_url_origin" => "https://github.com/tuist/tuist",
            "project_id" => project.id
          }
        )
      end)
    end
  end
end
