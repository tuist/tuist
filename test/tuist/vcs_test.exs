defmodule Tuist.VCSTest do
  use ExUnit.Case, async: false
  use Tuist.StubCase, billing: true
  alias Tuist.PreviewsFixtures
  use Tuist.DataCase
  use Mimic

  alias Tuist.GitHub
  alias Tuist.Billing
  alias Tuist.Accounts
  alias Tuist.VCS
  alias Tuist.VCS.Comment
  alias Tuist.Environment
  alias Tuist.ProjectsFixtures
  alias Tuist.CommandEventsFixtures

  @default_headers [
    {"Accept", "application/vnd.github.v3+json"},
    {"Authorization", "token github_token"}
  ]

  setup do
    GitHub.App
    |> stub(:get_app_installation_token_for_repository, fn "tuist/tuist" ->
      {:ok, %{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
    end)

    :ok
  end

  describe "get_user_permission/1" do
    test "returns user permission when admin" do
      # Given
      Billing |> stub(:start_trial, fn _ -> :ok end)

      user =
        Accounts.find_or_create_user_from_oauth2(%{
          provider: :github,
          uid: 123,
          info: %{
            email: "tuist@tuist.io"
          }
        })

      GitHub.Client
      |> expect(:get_user_by_id, fn %{id: "123", repository_full_handle: "tuist/tuist"} ->
        {:ok, %VCS.User{username: "tuist"}}
      end)

      GitHub.Client
      |> expect(:get_user_permission, fn %{
                                           repository_full_handle: "tuist/tuist",
                                           username: "tuist"
                                         } ->
        {:ok, %VCS.Repositories.Permission{permission: "admin"}}
      end)

      # When
      got =
        VCS.get_user_permission(%{
          user: user,
          repository: %VCS.Repositories.Repository{
            provider: :github,
            full_handle: "tuist/tuist",
            default_branch: "main"
          }
        })

      # Then
      assert got == {:ok, %VCS.Repositories.Permission{permission: "admin"}}
    end
  end

  describe "connected/1" do
    test "returns true when connected" do
      # Given
      Environment
      |> stub(:github_app_configured?, fn -> true end)

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

    test "returns false when the GitHub app is not configured" do
      # Given
      Environment
      |> stub(:github_app_configured?, fn -> false end)

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
      Environment
      |> stub(:github_app_configured?, fn -> false end)

      project =
        ProjectsFixtures.project_fixture(vcs_repository_full_handle: nil)

      # When
      got = VCS.connected?(%{project: project, repository_full_handle: "tuist/tuist"})

      # Then
      assert got == false
    end

    test "returns false when the connected repositor full handles' do not match" do
      # Given
      Environment
      |> stub(:github_app_configured?, fn -> false end)

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

      GitHub.Client
      |> expect(:get_repository, fn "tuist/tuist" ->
        {:ok,
         %VCS.Repositories.Repository{
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
                %VCS.Repositories.Repository{
                  provider: :github,
                  full_handle: "tuist/tuist",
                  default_branch: "main"
                }}
    end

    test "returns repository with username" do
      # Given
      repository_url = "https://tuist@github.com/tuist/tuist.git"

      GitHub.Client
      |> expect(:get_repository, fn "tuist/tuist" ->
        {:ok,
         %VCS.Repositories.Repository{
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
                %VCS.Repositories.Repository{
                  provider: :github,
                  full_handle: "tuist/tuist",
                  default_branch: "main"
                }}
    end

    test "returns repository with .git suffix" do
      # Given
      repository_url = "https://github.com/tuist/tuist.git"

      GitHub.Client
      |> expect(:get_repository, fn "tuist/tuist" ->
        {:ok,
         %VCS.Repositories.Repository{
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
                %VCS.Repositories.Repository{
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
      Environment
      |> stub(:github_app_client_id, fn -> "client_id" end)

      Environment
      |> stub(:github_app_configured?, fn -> true end)

      :ok
    end

    test "creates a comment with a full report" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      preview_one = PreviewsFixtures.preview_fixture(project: project, display_name: "App")

      _preview_command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          git_ref: @git_ref,
          project_id: project.id,
          preview_id: preview_one.id,
          git_commit_sha: @git_commit_sha,
          created_at: ~N[2024-04-30 03:00:00]
        )

      preview_two = PreviewsFixtures.preview_fixture(project: project, display_name: "App")

      _preview_command_event_two =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          git_ref: @git_ref,
          project_id: project.id,
          preview_id: preview_two.id,
          git_commit_sha: @git_commit_sha,
          created_at: ~N[2024-04-30 02:00:00]
        )

      preview_three =
        PreviewsFixtures.preview_fixture(project: project, display_name: "WatchApp")

      _preview_command_event_three =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          git_ref: @git_ref,
          project_id: project.id,
          preview_id: preview_three.id,
          git_commit_sha: @git_commit_sha,
          created_at: ~N[2024-04-30 01:00:00]
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

      Req
      |> stub(:get, fn [
                         headers: @default_headers,
                         url: "https://api.github.com/repos/tuist/tuist/issues/1/comments"
                       ] ->
        {:ok, %Req.Response{status: 200, body: []}}
      end)

      commit_link = "[123456789](#{@git_remote_url_origin}/commit/#{@git_commit_sha})"

      expected_body =
        """
        ### 🛠️ Tuist Run Report 🛠️

        #### Tuist Previews 📦

        | App | Commit |
        | - | - |
        | [App](https://tuist.io/previews/#{preview_one.id}) | #{commit_link} |
        | [WatchApp](https://tuist.io/previews/#{preview_three.id}) | #{commit_link} |


        #### Tuist Tests 🧪

        | Command | Status | Cache hit rate | Tests | Skipped | Ran | Commit |
        |:-:|:-:|:-:|:-:|:-:|:-:|:-:|
        | [test](https://tuist.io/runs/#{test_command_event_one.id}) | ✅ | 0 % | 0 | 0 | 0 | #{commit_link} |
        | [test App](https://tuist.io/runs/#{test_command_event_two.id}) | ❌ | 50 % | 4 | 3 | 1 | #{commit_link} |

        """

      Req
      |> stub(:post, fn [
                          headers: @default_headers,
                          url: "https://api.github.com/repos/tuist/tuist/issues/1/comments",
                          json: %{body: ^expected_body}
                        ] ->
        {:ok, %Req.Response{status: 200, body: %{}}}
      end)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        command_name: "share",
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.io/previews/#{preview.id}" end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.io/runs/#{command_event.id}"
        end
      })
    end

    test "creates a comment when full handle and provider is the same but url is different" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      preview = PreviewsFixtures.preview_fixture(project: project, display_name: "App")

      _preview_command_event =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          git_ref: @git_ref,
          project_id: project.id,
          preview_id: preview.id,
          git_commit_sha: @git_commit_sha,
          created_at: ~N[2024-04-30 03:00:00]
        )

      GitHub.Client
      |> expect(:get_comments, fn _ -> {:ok, []} end)

      GitHub.Client
      |> expect(:create_comment, fn %{
                                      repository_full_handle: "tuist/tuist",
                                      issue_id: "1",
                                      body: _
                                    } ->
        {:ok, %{}}
      end)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        command_name: "share",
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: "https://tuist@github.com/tuist/tuist",
        preview_url: fn %{preview: preview} -> "https://tuist.io/previews/#{preview.id}" end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.io/runs/#{command_event.id}"
        end
      })
    end

    test "creates a comment when full handle and provider is the same and the origin is using SSH" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      preview = PreviewsFixtures.preview_fixture(project: project, display_name: "App")

      _preview_command_event =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          git_ref: @git_ref,
          project_id: project.id,
          preview_id: preview.id,
          git_commit_sha: @git_commit_sha,
          created_at: ~N[2024-04-30 03:00:00]
        )

      GitHub.Client
      |> expect(:get_comments, fn _ -> {:ok, []} end)

      GitHub.Client
      |> expect(:create_comment, fn %{
                                      repository_full_handle: "tuist/tuist",
                                      issue_id: "1",
                                      body: _
                                    } ->
        {:ok, %{}}
      end)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        command_name: "share",
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: "git@github.com:tuist/tuist.git",
        preview_url: fn %{preview: preview} -> "https://tuist.io/previews/#{preview.id}" end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.io/runs/#{command_event.id}"
        end
      })
    end

    test "updates a comment if one already exists" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      preview = PreviewsFixtures.preview_fixture(project: project, display_name: "App")

      _preview_command_event =
        CommandEventsFixtures.command_event_fixture(
          name: "share",
          git_ref: @git_ref,
          project_id: project.id,
          preview_id: preview.id,
          git_commit_sha: "1234567890"
        )

      GitHub.Client
      |> expect(:get_comments, fn _ ->
        {:ok,
         [
           %Comment{
             id: 1,
             client_id: "client_id"
           }
         ]}
      end)

      GitHub.App
      |> stub(:get_app_installation_token_for_repository, fn "tuist/tuist" ->
        {:ok, %{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
      end)

      Req
      |> stub(:patch, fn [
                           headers: [
                             {"Accept", "application/vnd.github.v3+json"},
                             {"Authorization", "token github_token"}
                           ],
                           url: "https://api.github.com/repos/tuist/tuist/issues/comments/1",
                           json: %{body: _}
                         ] ->
        {:ok, %Req.Response{status: 200, body: %{}}}
      end)

      GitHub.Client
      |> reject(:create_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        command_name: "test",
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.io/previews/#{preview.id}" end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.io/runs/#{command_event.id}"
        end
      })
    end

    test "does not create a comment when there is nothing to report" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      GitHub.Client
      |> expect(:get_comments, fn _ -> {:ok, [%{client_id: nil}]} end)

      GitHub.Client
      |> reject(:create_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        command_name: "test",
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.io/previews/#{preview.id}" end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.io/runs/#{command_event.id}"
        end
      })
    end

    test "does not create a comment when the command is not reportable" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      GitHub.Client
      |> reject(:get_comments, 1)

      GitHub.Client
      |> reject(:create_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        command_name: "generate",
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.io/previews/#{preview.id}" end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.io/runs/#{command_event.id}"
        end
      })
    end

    test "does not create a comment when the GitHub app is not configured" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      Environment
      |> stub(:github_app_configured?, fn -> false end)

      GitHub.Client
      |> reject(:get_comments, 1)

      GitHub.Client
      |> reject(:create_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        command_name: "test",
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.io/previews/#{preview.id}" end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.io/runs/#{command_event.id}"
        end
      })
    end

    test "does not create a comment when the git ref is not a pull request" do
      # Given
      project = ProjectsFixtures.project_fixture()

      GitHub.Client
      |> reject(:get_comments, 1)

      GitHub.Client
      |> reject(:create_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        command_name: "test",
        git_commit_sha: @git_commit_sha,
        git_ref: "tags/1.0.0",
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.io/previews/#{preview.id}" end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.io/runs/#{command_event.id}"
        end
      })
    end

    test "does not create a comment when the git ref is missing" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      GitHub.Client
      |> reject(:get_comments, 1)

      GitHub.Client
      |> reject(:create_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        command_name: "test",
        git_ref: nil,
        git_commit_sha: @git_commit_sha,
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.io/previews/#{preview.id}" end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.io/runs/#{command_event.id}"
        end
      })
    end

    test "does not create a comment when the git remote url origin is missing" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/tuist",
          vcs_provider: :github
        )

      GitHub.Client
      |> reject(:get_comments, 1)

      GitHub.Client
      |> reject(:create_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        command_name: "test",
        git_remote_url_origin: nil,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        preview_url: fn %{preview: preview} -> "https://tuist.io/previews/#{preview.id}" end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.io/runs/#{command_event.id}"
        end
      })
    end

    test "does not create a comment when the git remote url origin has a different handle" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_repository_full_handle: "tuist/different-handle",
          vcs_provider: :github
        )

      GitHub.Client
      |> reject(:get_comments, 1)

      GitHub.Client
      |> reject(:create_comment, 1)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        command_name: "test",
        git_remote_url_origin: @git_remote_url_origin,
        git_commit_sha: @git_commit_sha,
        git_ref: @git_ref,
        preview_url: fn %{preview: preview} -> "https://tuist.io/previews/#{preview.id}" end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.io/runs/#{command_event.id}"
        end
      })
    end
  end
end
