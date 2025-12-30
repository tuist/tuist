defmodule Tuist.VCSTest do
  use ExUnit.Case, async: false
  use TuistTestSupport.Cases.StubCase, billing: true
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Environment
  alias Tuist.GitHub
  alias Tuist.GitHub.Client
  alias Tuist.KeyValueStore
  alias Tuist.Runs
  alias Tuist.VCS
  alias Tuist.VCS.Comment
  alias Tuist.VCS.GitHubAppInstallation
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.BundlesFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures

  @default_headers [
    {"Accept", "application/vnd.github.v3+json"},
    {"Authorization", "token github_token"}
  ]

  setup do
    stub(GitHub.App, :get_installation_token, fn _installation_id ->
      {:ok, %{token: "github_token", expires_at: ~U[2024-04-30 10:30:31Z]}}
    end)

    stub(Environment, :github_app_client_id, fn -> "client_id" end)

    :ok
  end

  describe "ci_run_url/1" do
    test "returns GitHub Actions URL for github provider" do
      ci_metadata = %{
        ci_provider: :github,
        ci_run_id: "19683527895",
        ci_project_handle: "tuist/tuist"
      }

      assert VCS.ci_run_url(ci_metadata) == "https://github.com/tuist/tuist/actions/runs/19683527895"
    end

    test "returns GitLab pipeline URL for gitlab provider with default host" do
      ci_metadata = %{
        ci_provider: :gitlab,
        ci_run_id: "987654321",
        ci_project_handle: "group/project"
      }

      assert VCS.ci_run_url(ci_metadata) == "https://gitlab.com/group/project/-/pipelines/987654321"
    end

    test "returns GitLab pipeline URL for gitlab provider with custom host" do
      ci_metadata = %{
        ci_provider: :gitlab,
        ci_run_id: "987654321",
        ci_project_handle: "group/project",
        ci_host: "gitlab.example.com"
      }

      assert VCS.ci_run_url(ci_metadata) == "https://gitlab.example.com/group/project/-/pipelines/987654321"
    end

    test "returns GitLab pipeline URL with default host when ci_host is empty string" do
      ci_metadata = %{
        ci_provider: :gitlab,
        ci_run_id: "987654321",
        ci_project_handle: "group/project",
        ci_host: ""
      }

      assert VCS.ci_run_url(ci_metadata) == "https://gitlab.com/group/project/-/pipelines/987654321"
    end

    test "returns Bitrise build URL for bitrise provider" do
      ci_metadata = %{
        ci_provider: :bitrise,
        ci_run_id: "abc123def",
        ci_project_handle: "ignored"
      }

      assert VCS.ci_run_url(ci_metadata) == "https://app.bitrise.io/build/abc123def"
    end

    test "returns CircleCI pipeline URL for circleci provider" do
      ci_metadata = %{
        ci_provider: :circleci,
        ci_run_id: "12345",
        ci_project_handle: "tuist/tuist"
      }

      assert VCS.ci_run_url(ci_metadata) == "https://app.circleci.com/pipelines/github/tuist/tuist/12345"
    end

    test "returns Buildkite builds URL for buildkite provider" do
      ci_metadata = %{
        ci_provider: :buildkite,
        ci_run_id: "67890",
        ci_project_handle: "tuist/pipeline"
      }

      assert VCS.ci_run_url(ci_metadata) == "https://buildkite.com/tuist/pipeline/builds/67890"
    end

    test "returns Codemagic build URL for codemagic provider" do
      ci_metadata = %{
        ci_provider: :codemagic,
        ci_run_id: "build-abc123",
        ci_project_handle: "app-id-123"
      }

      assert VCS.ci_run_url(ci_metadata) == "https://codemagic.io/app/app-id-123/build/build-abc123"
    end

    test "returns nil when ci_run_id is nil" do
      ci_metadata = %{
        ci_provider: :github,
        ci_run_id: nil,
        ci_project_handle: "tuist/tuist"
      }

      assert VCS.ci_run_url(ci_metadata) == nil
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
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      preview_one =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          bundle_identifier: "dev.tuist.app",
          version: "1.0.0",
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
          bundle_identifier: "dev.tuist.app",
          version: "1.0.1",
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
          bundle_identifier: "dev.tuist.watchapp",
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

      {:ok, test_run_one} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: @git_ref,
          git_commit_sha: @git_commit_sha,
          status: "success",
          scheme: "test",
          duration: 0,
          macos_version: "11.2.3",
          xcode_version: "12.4",
          is_ci: false,
          ran_at: ~N[2024-04-30 03:00:00],
          test_modules: []
        })

      _test_command_event_one =
        CommandEventsFixtures.command_event_fixture(
          name: "test",
          git_ref: @git_ref,
          project_id: project.id,
          command_arguments: ["test"],
          git_commit_sha: @git_commit_sha,
          created_at: ~N[2024-04-30 03:00:00],
          test_run_id: test_run_one.id
        )

      {:ok, test_run_two} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: @git_ref,
          git_commit_sha: @git_commit_sha,
          status: "failure",
          scheme: "test App",
          duration: 1000,
          macos_version: "11.2.3",
          xcode_version: "12.4",
          is_ci: false,
          ran_at: ~N[2024-04-30 04:00:00],
          test_modules: [
            %{
              name: "AppTests",
              status: "failure",
              duration: 1000,
              test_cases: [
                %{name: "test1", status: "success", duration: 250},
                %{name: "test2", status: "success", duration: 250},
                %{name: "test3", status: "success", duration: 250},
                %{name: "test4", status: "failure", duration: 250}
              ]
            }
          ]
        })

      _test_command_event_two =
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
          status: :failure,
          test_run_id: test_run_two.id
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

        | Scheme | Status | Cache hit rate | Tests | Skipped | Ran | Commit |
        |:-:|:-:|:-:|:-:|:-:|:-:|:-:|
        | [test](https://tuist.dev/test_runs/#{test_run_one.id}) | ✅ | 0 % | 0 | 0 | 0 | #{commit_link} |
        | [test App](https://tuist.dev/test_runs/#{test_run_two.id}) | ❌ | 50 % | 4 | 3 | 1 | #{commit_link} |

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
        test_run_url: fn %{test_run: test_run} -> "https://tuist.dev/test_runs/#{test_run.id}" end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "creates a comment with ipa previews" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      preview_one =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          bundle_identifier: "dev.tuist.app",
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
          bundle_identifier: "dev.tuist.watchapp",
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
        test_run_url: fn %{test_run: test_run} -> "https://tuist.dev/test_runs/#{test_run.id}" end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "creates a comment when full handle and provider is the same but url is different" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
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

      expect(Client, :get_comments, fn _ -> {:ok, []} end)

      expect(Client, :create_comment, fn %{
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
        test_run_url: fn %{test_run: test_run} -> "https://tuist.dev/test_runs/#{test_run.id}" end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "creates a comment when full handle and provider is the same and the origin is using SSH" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
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

      expect(Client, :get_comments, fn _ -> {:ok, []} end)

      expect(Client, :create_comment, fn %{
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
        test_run_url: fn %{test_run: test_run} -> "https://tuist.dev/test_runs/#{test_run.id}" end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "updates a comment if one already exists" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
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

      expect(Client, :get_comments, fn _ ->
        {:ok,
         [
           %Comment{
             id: 1,
             client_id: "client_id",
             body: "### 🛠️ Tuist Run Report 🛠️\n\nSome existing content"
           }
         ]}
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

      reject(Client, :create_comment, 1)

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
        test_run_url: fn %{test_run: test_run} -> "https://tuist.dev/test_runs/#{test_run.id}" end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "does not create a comment when there is nothing to report" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      expect(Client, :get_comments, fn _ -> {:ok, []} end)
      reject(Client, :create_comment, 1)

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
        test_run_url: fn %{test_run: test_run} -> "https://tuist.dev/test_runs/#{test_run.id}" end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "creates a new comment when existing comment has same client_id but is not a Tuist Run Report" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
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
      expect(Client, :get_comments, fn _ ->
        {:ok,
         [
           %Comment{
             id: 1,
             client_id: "client_id",
             body: "This is a different comment from the Tuist bot"
           }
         ]}
      end)

      expect(Client, :create_comment, fn %{
                                           repository_full_handle: "tuist/tuist",
                                           issue_id: "1",
                                           body: body
                                         } ->
        assert String.starts_with?(body, "### 🛠️ Tuist Run Report 🛠️")
        {:ok, %{id: 2}}
      end)

      reject(Client, :update_comment, 1)

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
        test_run_url: fn %{test_run: test_run} -> "https://tuist.dev/test_runs/#{test_run.id}" end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "does not create a comment when the GitHub app is not configured" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      stub(Environment, :github_app_configured?, fn -> false end)
      reject(Client, :get_comments, 1)
      reject(Client, :create_comment, 1)

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
        test_run_url: fn %{test_run: test_run} -> "https://tuist.dev/test_runs/#{test_run.id}" end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "does not create a comment when the git ref is not a pull request" do
      # Given
      project = ProjectsFixtures.project_fixture()

      reject(Client, :get_comments, 1)
      reject(Client, :create_comment, 1)

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
        test_run_url: fn %{test_run: test_run} -> "https://tuist.dev/test_runs/#{test_run.id}" end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "does not create a comment when the git ref is missing" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      reject(Client, :get_comments, 1)
      reject(Client, :create_comment, 1)

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
        test_run_url: fn %{test_run: test_run} -> "https://tuist.dev/test_runs/#{test_run.id}" end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "does not create a comment when the git remote url origin is missing" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      reject(Client, :get_comments, 1)
      reject(Client, :create_comment, 1)

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
        test_run_url: fn %{test_run: test_run} -> "https://tuist.dev/test_runs/#{test_run.id}" end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "does not create a comment when the git remote url origin has a different handle" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/different-handle",
            provider: :github
          ]
        )

      reject(Client, :get_comments, 1)
      reject(Client, :create_comment, 1)

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
        test_run_url: fn %{test_run: test_run} -> "https://tuist.dev/test_runs/#{test_run.id}" end,
        bundle_url: fn _ -> "" end,
        build_url: fn _ -> "" end
      })
    end

    test "creates a comment with bundles" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
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
        test_run_url: fn _ -> "" end,
        bundle_url: fn %{bundle: bundle} -> "https://tuist.dev/bundles/#{bundle.id}" end,
        build_url: fn _ -> "" end
      })
    end

    test "creates a comment with builds" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
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
        test_run_url: fn _ -> "" end,
        bundle_url: fn _ -> "" end,
        build_url: fn %{build: build} -> "https://tuist.dev/build-runs/#{build.id}" end
      })
    end

    test "handles different git_ref suffixes (head/merge) connected with the same PR correctly" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          display_name: "App",
          git_ref: "refs/pull/1/head",
          git_commit_sha: @git_commit_sha,
          inserted_at: ~N[2024-04-30 03:00:00]
        )

      _app_build =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          project: project,
          display_name: "App"
        )

      {:ok, test_run} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/pull/1/merge",
          git_commit_sha: @git_commit_sha,
          status: "success",
          scheme: "test",
          duration: 0,
          macos_version: "11.2.3",
          xcode_version: "12.4",
          is_ci: false,
          ran_at: ~N[2024-04-30 04:00:00],
          test_modules: []
        })

      _test_command_event =
        CommandEventsFixtures.command_event_fixture(
          name: "test",
          git_ref: "refs/pull/1/merge",
          project_id: project.id,
          command_arguments: ["test"],
          git_commit_sha: @git_commit_sha,
          created_at: ~N[2024-04-30 04:00:00],
          test_run_id: test_run.id
        )

      bundle =
        BundlesFixtures.bundle_fixture(
          project: project,
          install_size: 1000,
          download_size: 3000,
          git_ref: "refs/pull/1/head",
          git_commit_sha: @git_commit_sha,
          inserted_at: ~U[2024-01-01 05:00:00Z]
        )

      {:ok, build_run} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          scheme: "MyApp",
          status: :success,
          duration: 45_000,
          git_commit_sha: @git_commit_sha,
          git_ref: "refs/pull/1/merge"
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
        | [App](https://tuist.dev/previews/#{preview.id}) | #{commit_link} |


        #### Tests 🧪

        | Scheme | Status | Cache hit rate | Tests | Skipped | Ran | Commit |
        |:-:|:-:|:-:|:-:|:-:|:-:|:-:|
        | [test](https://tuist.dev/test_runs/#{test_run.id}) | ✅ | 0 % | 0 | 0 | 0 | #{commit_link} |


        #### Builds 🔨

        | Scheme | Status | Duration | Commit |
        |:-:|:-:|:-:|:-:|
        | [MyApp](https://tuist.dev/build-runs/#{build_run.id}) | ✅ | 45.0s | #{commit_link} |


        #### Bundles 🧰

        | Bundle | Commit | Install size | Download size |
        | - | - | - | - |
        | [App](https://tuist.dev/bundles/#{bundle.id}) | #{commit_link} | <div align=\"center\">1.0 KB</div> | <div align=\"center\">3.0 KB</div> |

        """

      expect(Req, :post, fn opts ->
        assert opts[:json] == %{body: expected_body}

        {:ok, %Req.Response{status: 200, body: %{}}}
      end)

      # When / Then
      VCS.post_vcs_pull_request_comment(%{
        project: project,
        git_commit_sha: @git_commit_sha,
        git_ref: "refs/pull/1/merge",
        git_remote_url_origin: @git_remote_url_origin,
        preview_url: fn %{preview: preview} -> "https://tuist.dev/previews/#{preview.id}" end,
        preview_qr_code_url: fn %{preview: preview} ->
          "https://tuist.dev/previews/#{preview.id}/qr-code.svg"
        end,
        command_run_url: fn %{command_event: command_event} ->
          "https://tuist.dev/runs/#{command_event.id}"
        end,
        test_run_url: fn %{test_run: test_run} -> "https://tuist.dev/test_runs/#{test_run.id}" end,
        bundle_url: fn %{bundle: bundle} -> "https://tuist.dev/bundles/#{bundle.id}" end,
        build_url: fn %{build: build} -> "https://tuist.dev/build-runs/#{build.id}" end
      })
    end

    test "does not show size delta when there is no last bundle" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
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
        test_run_url: fn _ -> "" end,
        bundle_url: fn %{bundle: bundle} -> "https://tuist.dev/bundles/#{bundle.id}" end,
        build_url: fn _ -> "" end
      })
    end

    test "shows Unknown when download_size is nil" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
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
        test_run_url: fn _ -> "" end,
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
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      expect(Client, :create_comment, fn %{
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
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      reject(Client, :create_comment, 1)

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
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      reject(Client, :create_comment, 1)

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
          vcs_connection: [
            repository_full_handle: "different/repo",
            provider: :github
          ]
        )

      reject(Client, :create_comment, 1)

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
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      reject(Client, :create_comment, 1)

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
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      expect(Client, :create_comment, fn %{
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
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      comment_params = %{
        repository_full_handle: "tuist/tuist",
        comment_id: "123456",
        body: "Updated comment body",
        project: project
      }

      expect(Client, :update_comment, fn %{
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
          vcs_connection: [
            repository_full_handle: "different/repo",
            provider: :github
          ]
        )

      comment_params = %{
        repository_full_handle: "tuist/tuist",
        comment_id: "123456",
        body: "Updated comment body",
        project: project
      }

      reject(Client, :update_comment, 1)

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
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      comment_params = %{
        repository_full_handle: "tuist/tuist",
        comment_id: "123456",
        body: "Updated comment body",
        project: project
      }

      reject(Client, :update_comment, 1)

      # When
      result = VCS.update_comment(comment_params)

      # Then
      assert {:error, :repository_not_connected} = result
    end

    test "handles GitHub client errors" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      comment_params = %{
        repository_full_handle: "tuist/tuist",
        comment_id: "123456",
        body: "Updated comment body",
        project: project
      }

      expect(Client, :update_comment, fn %{
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
          vcs_connection: [
            repository_full_handle: "tuist/tuist",
            provider: :github
          ]
        )

      comment_ids = ["123", "456789", "999"]

      for comment_id <- comment_ids do
        comment_params = %{
          repository_full_handle: "tuist/tuist",
          comment_id: comment_id,
          body: "Updated comment for ID #{comment_id}",
          project: project
        }

        expect(Client, :update_comment, fn %{
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

  # GitHub App Installation tests

  describe "get_github_app_installation_by_installation_id/1" do
    test "returns the GitHub app installation when it exists" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "12345"

      {:ok, github_app_installation} =
        %GitHubAppInstallation{}
        |> GitHubAppInstallation.changeset(%{
          account_id: account.id,
          installation_id: installation_id
        })
        |> Repo.insert()

      # When
      result = VCS.get_github_app_installation_by_installation_id(installation_id)

      # Then
      assert {:ok, fetched_installation} = result
      assert fetched_installation.id == github_app_installation.id
      assert fetched_installation.installation_id == installation_id
      assert fetched_installation.account_id == account.id
    end

    test "returns error when GitHub app installation does not exist" do
      # Given
      non_existent_installation_id = "99999"

      # When
      result = VCS.get_github_app_installation_by_installation_id(non_existent_installation_id)

      # Then
      assert result == {:error, :not_found}
    end
  end

  describe "delete_github_app_installation/1" do
    test "successfully deletes a GitHub app installation" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "67890"

      {:ok, github_app_installation} =
        %GitHubAppInstallation{}
        |> GitHubAppInstallation.changeset(%{
          account_id: account.id,
          installation_id: installation_id
        })
        |> Repo.insert()

      # When
      result = VCS.delete_github_app_installation(github_app_installation)

      # Then
      assert {:ok, deleted_installation} = result
      assert deleted_installation.id == github_app_installation.id

      # Verify it's actually deleted
      assert VCS.get_github_app_installation_by_installation_id(installation_id) == {:error, :not_found}
    end

    test "returns error when trying to delete stale installation" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account

      {:ok, github_app_installation} =
        %GitHubAppInstallation{}
        |> GitHubAppInstallation.changeset(%{
          account_id: account.id,
          installation_id: "temp-id"
        })
        |> Repo.insert()

      # Delete it first to make it stale
      {:ok, _} = Repo.delete(github_app_installation)

      # When
      result = VCS.delete_github_app_installation(github_app_installation)

      # Then
      assert {:error, changeset} = result
      assert changeset.errors[:id] == {"is stale", [stale: true]}
    end
  end

  describe "update_github_app_installation/2" do
    test "successfully updates a GitHub app installation with html_url" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "11111"
      html_url = "https://github.com/organizations/tuist/settings/installations/11111"

      {:ok, github_app_installation} =
        %GitHubAppInstallation{}
        |> GitHubAppInstallation.changeset(%{
          account_id: account.id,
          installation_id: installation_id
        })
        |> Repo.insert()

      # When
      result = VCS.update_github_app_installation(github_app_installation, %{html_url: html_url})

      # Then
      assert {:ok, updated_installation} = result
      assert updated_installation.html_url == html_url
      assert updated_installation.installation_id == installation_id
      assert updated_installation.account_id == account.id
    end

    test "returns error with invalid data" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account

      {:ok, github_app_installation} =
        %GitHubAppInstallation{}
        |> GitHubAppInstallation.changeset(%{
          account_id: account.id,
          installation_id: "22222"
        })
        |> Repo.insert()

      # When
      result = VCS.update_github_app_installation(github_app_installation, %{html_url: 123})

      # Then
      assert {:error, changeset} = result
      assert changeset.errors[:html_url] == {"is invalid", [type: :string, validation: :cast]}
    end
  end

  describe "create_github_app_installation/1" do
    test "successfully creates a GitHub app installation with valid attributes" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "54321"

      attrs = %{
        account_id: account.id,
        installation_id: installation_id
      }

      # When
      result = VCS.create_github_app_installation(attrs)

      # Then
      assert {:ok, github_app_installation} = result
      assert github_app_installation.account_id == account.id
      assert github_app_installation.installation_id == installation_id
    end
  end

  describe "get_github_app_installation_repositories/1" do
    test "returns all repositories from single page with caching" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "repo_test_123"

      {:ok, github_app_installation} =
        VCS.create_github_app_installation(%{
          account_id: account.id,
          installation_id: installation_id
        })

      expected_repositories = [
        %{id: 1, name: "repo1", full_name: "tuist/repo1", private: false, default_branch: "main"},
        %{id: 2, name: "repo2", full_name: "tuist/repo2", private: true, default_branch: "master"}
      ]

      expect(KeyValueStore, :get_or_update, fn key, opts, fun ->
        assert key == [VCS, "repositories", installation_id]
        assert Keyword.get(opts, :ttl) == to_timeout(minute: 15)
        fun.()
      end)

      expect(Client, :list_installation_repositories, fn ^installation_id, [] ->
        {:ok, %{meta: %{next_url: nil}, repositories: expected_repositories}}
      end)

      # When
      result = VCS.get_github_app_installation_repositories(github_app_installation)

      # Then
      assert {:ok, repositories} = result
      assert repositories == expected_repositories
    end

    test "returns all repositories from multiple pages with caching" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "pagination_test_456"

      {:ok, github_app_installation} =
        VCS.create_github_app_installation(%{
          account_id: account.id,
          installation_id: installation_id
        })

      page1_repos = [
        %{id: 1, name: "repo1", full_name: "tuist/repo1", private: false, default_branch: "main"}
      ]

      page2_repos = [
        %{id: 2, name: "repo2", full_name: "tuist/repo2", private: true, default_branch: "master"}
      ]

      expect(KeyValueStore, :get_or_update, fn key, opts, fun ->
        assert key == [VCS, "repositories", installation_id]
        assert Keyword.get(opts, :ttl) == to_timeout(minute: 15)
        fun.()
      end)

      expect(Client, :list_installation_repositories, 2, fn
        ^installation_id, [] ->
          {:ok,
           %{
             meta: %{next_url: "https://api.github.com/installation/repositories?page=2"},
             repositories: page1_repos
           }}

        ^installation_id, [next_url: "https://api.github.com/installation/repositories?page=2"] ->
          {:ok, %{meta: %{next_url: nil}, repositories: page2_repos}}
      end)

      # When
      result = VCS.get_github_app_installation_repositories(github_app_installation)

      # Then
      assert {:ok, repositories} = result
      assert repositories == page1_repos ++ page2_repos
    end

    test "returns error when GitHub client fails on first page" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "error_test_789"

      {:ok, github_app_installation} =
        VCS.create_github_app_installation(%{
          account_id: account.id,
          installation_id: installation_id
        })

      error_message = "GitHub API error"

      expect(KeyValueStore, :get_or_update, fn key, opts, fun ->
        assert key == [VCS, "repositories", installation_id]
        assert Keyword.get(opts, :ttl) == to_timeout(minute: 15)
        fun.()
      end)

      expect(Client, :list_installation_repositories, fn ^installation_id, [] ->
        {:error, error_message}
      end)

      # When
      result = VCS.get_github_app_installation_repositories(github_app_installation)

      # Then
      assert {:error, ^error_message} = result
    end
  end

  describe "get_github_app_installation_url/1" do
    test "generates GitHub app installation URL with state token for account" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      app_name = "test-tuist-app"

      expect(Environment, :github_app_name, fn -> app_name end)

      # When
      result = VCS.get_github_app_installation_url(account)

      # Then
      assert String.starts_with?(result, "https://github.com/apps/#{app_name}/installations/new?state=")

      # Extract and verify the state token
      state_token = result |> String.split("state=") |> List.last()
      account_id = account.id
      assert {:ok, ^account_id} = VCS.verify_github_state_token(state_token)
    end
  end

  describe "account deletion cascades" do
    test "deletes associated github_app_installation when account is deleted" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account

      # Create a GitHub app installation for the account
      github_app_installation = VCSFixtures.github_app_installation_fixture(account_id: account.id)

      # When
      {:ok, _deleted_account} = Repo.delete(account)

      # Then
      # Verify the GitHub app installation was cascade deleted
      assert Repo.get(GitHubAppInstallation, github_app_installation.id) == nil
    end
  end

  # GitHub State Token tests

  describe "generate_github_state_token/1" do
    test "generates a token for a given account ID" do
      # Given
      account_id = 123

      # When
      token = VCS.generate_github_state_token(account_id)

      # Then
      assert is_binary(token)
      assert String.length(token) > 0
    end

    test "generates different tokens for different account IDs" do
      # Given
      account_id_1 = 123
      account_id_2 = 456

      # When
      token_1 = VCS.generate_github_state_token(account_id_1)
      token_2 = VCS.generate_github_state_token(account_id_2)

      # Then
      assert token_1 != token_2
    end
  end

  describe "verify_github_state_token/1" do
    test "verifies a valid token and returns the account ID" do
      # Given
      account_id = 123
      token = VCS.generate_github_state_token(account_id)

      # When
      result = VCS.verify_github_state_token(token)

      # Then
      assert {:ok, ^account_id} = result
    end

    test "returns error for invalid token format" do
      # Given
      invalid_token = "invalid_token_format"

      # When
      result = VCS.verify_github_state_token(invalid_token)

      # Then
      assert {:error, _reason} = result
    end

    test "returns error for empty token" do
      # Given
      empty_token = ""

      # When
      result = VCS.verify_github_state_token(empty_token)

      # Then
      assert {:error, _reason} = result
    end

    test "returns error for nil token" do
      # When
      result = VCS.verify_github_state_token(nil)

      # Then
      assert {:error, _reason} = result
    end
  end

  # GitHub App Installation Schema tests

  describe "GitHubAppInstallation changeset/2" do
    test "is valid with valid attributes" do
      # Given
      account = AccountsFixtures.account_fixture()

      # When
      changeset =
        GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
          account_id: account.id,
          installation_id: "12345"
        })

      # Then
      assert changeset.valid?
    end

    test "is invalid without account_id" do
      # When
      changeset =
        GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
          installation_id: "12345"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).account_id
    end

    test "is invalid without installation_id" do
      # Given
      account = AccountsFixtures.account_fixture()

      # When
      changeset =
        GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
          account_id: account.id
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).installation_id
    end

    test "is invalid with non-existent account_id" do
      # Given
      non_existent_id = 99_999

      # When
      changeset =
        GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
          account_id: non_existent_id,
          installation_id: "12345"
        })

      # Then
      assert changeset.valid?

      # When
      assert {:error, changeset_with_error} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset_with_error).account_id
    end

    test "enforces unique constraint on account_id" do
      # Given
      account = AccountsFixtures.account_fixture()

      {:ok, _existing_installation} =
        Repo.insert(
          GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
            account_id: account.id,
            installation_id: "12345"
          })
        )

      # When
      changeset =
        GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
          account_id: account.id,
          installation_id: "67890"
        })

      # Then
      assert {:error, changeset_with_error} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset_with_error).account_id
    end

    test "enforces unique constraint on installation_id" do
      # Given
      account1 = AccountsFixtures.account_fixture()
      account2 = AccountsFixtures.account_fixture()

      {:ok, _existing_installation} =
        Repo.insert(
          GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
            account_id: account1.id,
            installation_id: "12345"
          })
        )

      # When
      changeset =
        GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
          account_id: account2.id,
          installation_id: "12345"
        })

      # Then
      assert {:error, changeset_with_error} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset_with_error).installation_id
    end
  end

  describe "GitHubAppInstallation update_changeset/2" do
    test "is valid with html_url" do
      # Given
      account = AccountsFixtures.account_fixture()

      {:ok, installation} =
        Repo.insert(
          GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
            account_id: account.id,
            installation_id: "12345"
          })
        )

      # When
      changeset =
        GitHubAppInstallation.update_changeset(installation, %{
          html_url: "https://github.com/settings/installations/12345"
        })

      # Then
      assert changeset.valid?
    end

    test "is valid without any attributes" do
      # Given
      account = AccountsFixtures.account_fixture()

      {:ok, installation} =
        Repo.insert(
          GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
            account_id: account.id,
            installation_id: "12345"
          })
        )

      # When
      changeset = GitHubAppInstallation.update_changeset(installation, %{})

      # Then
      assert changeset.valid?
    end
  end
end
