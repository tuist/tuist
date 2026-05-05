defmodule Tuist.Tests.Workers.ProcessXcresultWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Processor.XCResultProcessor
  alias Tuist.Tests.Workers.ProcessXcresultWorker

  setup :verify_on_exit!

  @storage_key "tuist/tests/test-xcresult.zip"

  setup do
    %{account: account} =
      TuistTestSupport.Fixtures.AccountsFixtures.user_fixture(preload: [:account])

    project = TuistTestSupport.Fixtures.ProjectsFixtures.project_fixture()

    %{account: account, project: project}
  end

  defp job_args(test_run_id, account_id, project_id, opts \\ []) do
    base = %{
      "test_run_id" => test_run_id,
      "storage_key" => @storage_key,
      "account_id" => account_id,
      "project_id" => project_id,
      "account_handle" => Keyword.get(opts, :account_handle, "test-account"),
      "project_handle" => Keyword.get(opts, :project_handle, "test-project"),
      "is_ci" => false,
      "git_branch" => "main",
      "git_commit_sha" => "abc123",
      "git_ref" => "refs/heads/main",
      "macos_version" => "15.0",
      "xcode_version" => "16.0",
      "model_identifier" => "Mac15,3",
      "scheme" => "App"
    }

    Enum.reduce(opts, base, fn
      {:extra, extra}, acc -> Map.merge(acc, extra)
      _, acc -> acc
    end)
  end

  defp oban_job(args, attempt \\ 1, max_attempts \\ 3) do
    %Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}
  end

  defp parsed_data do
    %{
      "test_plan_name" => "AppTests",
      "status" => "success",
      "duration" => 45.2,
      "test_modules" => [
        %{
          "name" => "AppModuleTests",
          "status" => "success",
          "duration" => 30.0,
          "test_suites" => [
            %{
              "name" => "AppSuite",
              "status" => "success",
              "duration" => 30.0
            }
          ],
          "test_cases" => [
            %{
              "name" => "test_example",
              "test_suite_name" => "AppSuite",
              "status" => "success",
              "duration" => 10.0,
              "failures" => [],
              "repetitions" => [],
              "attachments" => [
                %{
                  "attachment_id" => "att-001",
                  "file_name" => "screenshot.png",
                  "repetition_number" => nil
                }
              ]
            }
          ]
        }
      ]
    }
  end

  defp parsed_data_with_failure do
    %{
      "test_plan_name" => "AppTests",
      "status" => "failure",
      "duration" => 45.2,
      "test_modules" => [
        %{
          "name" => "AppModuleTests",
          "status" => "failure",
          "duration" => 30.0,
          "test_suites" => [
            %{
              "name" => "AppSuite",
              "status" => "failure",
              "duration" => 30.0
            }
          ],
          "test_cases" => [
            %{
              "name" => "test_failing",
              "test_suite_name" => "AppSuite",
              "status" => "failure",
              "duration" => 5.0,
              "failures" => [
                %{
                  "message" => "XCTAssertTrue failed",
                  "path" => "AppTests/AppTests.swift",
                  "line_number" => 42,
                  "issue_type" => "assertion_failure"
                }
              ],
              "repetitions" => []
            }
          ]
        }
      ]
    }
  end

  defp expect_local_parse(account, parsed) do
    expect(Tuist.Accounts, :get_account_by_id, fn _id -> {:ok, account} end)
    expect(Tuist.Storage, :download_to_file, fn _key, _path, _account -> {:ok, :done} end)
    expect(XCResultProcessor, :process_local, fn _path, _opts -> {:ok, parsed} end)
  end

  describe "perform/1 success path" do
    test "downloads + parses + creates the test run", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()
      expect_local_parse(account, parsed_data())

      expect(Tuist.Tests, :create_test, fn attrs ->
        assert attrs.id == test_run_id
        assert attrs.project_id == project.id
        assert attrs.account_id == account.id
        assert attrs.scheme == "AppTests"
        assert attrs.status == "success"
        assert attrs.duration == 45.2
        assert attrs.is_ci == false
        assert attrs.git_branch == "main"
        assert attrs.git_commit_sha == "abc123"
        assert attrs.xcode_version == "16.0"
        assert attrs.macos_version == "15.0"
        assert length(attrs.test_modules) == 1

        [module] = attrs.test_modules
        assert module["name"] == "AppModuleTests"
        assert module["status"] == "success"

        [test_case] = module["test_cases"]
        [attachment] = test_case["attachments"]
        assert attachment["attachment_id"] == "att-001"
        assert attachment["file_name"] == "screenshot.png"
        {:ok, %{id: test_run_id}}
      end)

      assert :ok ==
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id)))
    end

    test "passes failure status through unchanged", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()
      expect_local_parse(account, parsed_data_with_failure())

      expect(Tuist.Tests, :create_test, fn attrs ->
        assert attrs.status == "failure"

        [module] = attrs.test_modules
        assert module["status"] == "failure"

        [test_case] = module["test_cases"]
        assert test_case["status"] == "failure"
        assert length(test_case["failures"]) == 1

        [failure] = test_case["failures"]
        assert failure["message"] == "XCTAssertTrue failed"
        {:ok, %{id: test_run_id}}
      end)

      assert :ok ==
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id)))
    end

    test "normalises xcresult platform strings into the canonical snake-case form before passing them to create_test",
         %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()

      parsed =
        Map.put(parsed_data(), "run_destinations", [
          %{"name" => "iPhone 17", "platform" => "iOS Simulator", "os_version" => "26.4"},
          %{"name" => "iPad", "platform" => "iPadOS Simulator", "os_version" => "26.4"},
          %{"name" => "Apple Watch", "platform" => "watchOS Simulator", "os_version" => "11.0"},
          %{"name" => "Mac", "platform" => "macOS", "os_version" => "26.3"}
        ])

      expect_local_parse(account, parsed)

      expect(Tuist.Tests, :create_test, fn attrs ->
        assert attrs.run_destinations == [
                 %{name: "iPhone 17", platform: "ios_simulator", os_version: "26.4"},
                 %{name: "iPad", platform: "ios_simulator", os_version: "26.4"},
                 %{name: "Apple Watch", platform: "watchos_simulator", os_version: "11.0"},
                 %{name: "Mac", platform: "macos", os_version: "26.3"}
               ]

        {:ok, %{id: test_run_id}}
      end)

      assert :ok ==
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id)))
    end

    test "maps unrecognised platform strings to \"unknown\"", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()

      parsed =
        Map.put(parsed_data(), "run_destinations", [
          %{"name" => "Mystery Box", "platform" => "linuxOS", "os_version" => "1.0"}
        ])

      expect_local_parse(account, parsed)

      expect(Tuist.Tests, :create_test, fn attrs ->
        assert [%{platform: "unknown"}] = attrs.run_destinations
        {:ok, %{id: test_run_id}}
      end)

      assert :ok ==
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id)))
    end

    test "defaults run_destinations to an empty list when parsed data omits them", %{
      account: account,
      project: project
    } do
      test_run_id = Ecto.UUID.generate()
      expect_local_parse(account, parsed_data())

      expect(Tuist.Tests, :create_test, fn attrs ->
        assert attrs.run_destinations == []
        {:ok, %{id: test_run_id}}
      end)

      assert :ok ==
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id)))
    end

    test "uses test_plan_name from parsed data as scheme", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()
      expect_local_parse(account, parsed_data())

      expect(Tuist.Tests, :create_test, fn attrs ->
        assert attrs.scheme == "AppTests"
        {:ok, %{id: test_run_id}}
      end)

      assert :ok ==
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id)))
    end

    test "falls back to job args scheme when test_plan_name is nil", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()
      parsed_without_plan_name = %{parsed_data() | "test_plan_name" => nil}
      expect_local_parse(account, parsed_without_plan_name)

      expect(Tuist.Tests, :create_test, fn attrs ->
        assert attrs.scheme == "App"
        {:ok, %{id: test_run_id}}
      end)

      assert :ok ==
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id)))
    end

    test "passes ci_project_handle, build_run_id, shard_plan_id, and shard_index to create_test", %{
      account: account,
      project: project
    } do
      test_run_id = Ecto.UUID.generate()
      build_run_id = Ecto.UUID.generate()
      shard_plan_id = Ecto.UUID.generate()

      extra = %{
        "ci_project_handle" => "tuist/tuist",
        "build_run_id" => build_run_id,
        "shard_plan_id" => shard_plan_id,
        "shard_index" => 2
      }

      expect_local_parse(account, parsed_data())

      expect(Tuist.Tests, :create_test, fn attrs ->
        assert attrs.ci_project_handle == "tuist/tuist"
        assert attrs.build_run_id == build_run_id
        assert attrs.shard_plan_id == shard_plan_id
        assert attrs.shard_index == 2
        {:ok, %{id: test_run_id}}
      end)

      args = job_args(test_run_id, account.id, project.id, extra: extra)
      assert :ok == ProcessXcresultWorker.perform(oban_job(args))
    end
  end

  describe "perform/1 failure path" do
    test "returns error when the parser fails", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()

      expect(Tuist.Accounts, :get_account_by_id, fn _id -> {:ok, account} end)
      expect(Tuist.Storage, :download_to_file, fn _key, _path, _account -> {:ok, :done} end)

      expect(XCResultProcessor, :process_local, fn _path, _opts ->
        {:error, "parse failed"}
      end)

      assert {:error, "parse failed"} =
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id), 1, 3))
    end

    test "returns error when S3 download fails", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()

      expect(Tuist.Accounts, :get_account_by_id, fn _id -> {:ok, account} end)

      expect(Tuist.Storage, :download_to_file, fn _key, _path, _account ->
        {:error, {:http_error, 500, "server error"}}
      end)

      assert {:error, {:http_error, 500, "server error"}} =
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id), 1, 3))
    end

    test "marks test run as failed_processing on max attempts", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()

      expect(Tuist.Accounts, :get_account_by_id, fn _id -> {:ok, account} end)
      expect(Tuist.Storage, :download_to_file, fn _key, _path, _account -> {:ok, :done} end)

      expect(XCResultProcessor, :process_local, fn _path, _opts ->
        {:error, "parse failed"}
      end)

      expect(Tuist.Tests, :create_test, fn attrs ->
        assert attrs.id == test_run_id
        assert attrs.status == "failed_processing"
        assert attrs.duration == 0
        assert attrs.test_modules == []
        {:ok, %{id: test_run_id}}
      end)

      assert {:error, _} =
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id), 3, 3))
    end

    test "passes ci_project_handle through for failed_processing", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()

      extra = %{
        "ci_project_handle" => "tuist/tuist",
        "ci_run_id" => "12345",
        "ci_provider" => "github"
      }

      expect(Tuist.Accounts, :get_account_by_id, fn _id -> {:ok, account} end)
      expect(Tuist.Storage, :download_to_file, fn _key, _path, _account -> {:ok, :done} end)

      expect(XCResultProcessor, :process_local, fn _path, _opts ->
        {:error, "parse failed"}
      end)

      expect(Tuist.Tests, :create_test, fn attrs ->
        assert attrs.status == "failed_processing"
        assert attrs.ci_project_handle == "tuist/tuist"
        {:ok, %{id: test_run_id}}
      end)

      args = job_args(test_run_id, account.id, project.id, extra: extra)
      assert {:error, _} = ProcessXcresultWorker.perform(oban_job(args, 3, 3))
    end

    test "does not mark as failed_processing on non-final attempt", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()

      expect(Tuist.Accounts, :get_account_by_id, fn _id -> {:ok, account} end)
      expect(Tuist.Storage, :download_to_file, fn _key, _path, _account -> {:ok, :done} end)

      expect(XCResultProcessor, :process_local, fn _path, _opts ->
        {:error, "parse failed"}
      end)

      reject(&Tuist.Tests.create_test/1)

      assert {:error, _} =
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id), 1, 3))
    end
  end

  describe "perform/1 VCS comment refresh" do
    test "enqueues VCS comment after successful processing when vcs_comment_params present", %{
      account: account,
      project: project
    } do
      test_run_id = Ecto.UUID.generate()
      expect_local_parse(account, parsed_data())

      expect(Tuist.Tests, :create_test, fn _attrs -> {:ok, %{id: test_run_id}} end)

      vcs_params = %{
        "git_commit_sha" => "abc123",
        "git_ref" => "refs/pull/1/merge",
        "git_remote_url_origin" => "https://github.com/tuist/tuist",
        "project_id" => project.id
      }

      expect(Tuist.VCS, :enqueue_vcs_pull_request_comment, fn params ->
        assert params["git_commit_sha"] == "abc123"
        assert params["git_ref"] == "refs/pull/1/merge"
        assert params["git_remote_url_origin"] == "https://github.com/tuist/tuist"
        assert params["project_id"] == project.id
        {:ok, %{}}
      end)

      args =
        test_run_id
        |> job_args(account.id, project.id)
        |> Map.put("vcs_comment_params", vcs_params)

      assert :ok == ProcessXcresultWorker.perform(oban_job(args))
    end

    test "does not enqueue VCS comment when vcs_comment_params not present", %{
      account: account,
      project: project
    } do
      test_run_id = Ecto.UUID.generate()
      expect_local_parse(account, parsed_data())

      expect(Tuist.Tests, :create_test, fn _attrs -> {:ok, %{id: test_run_id}} end)
      reject(&Tuist.VCS.enqueue_vcs_pull_request_comment/1)

      assert :ok ==
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id)))
    end

    test "does not enqueue VCS comment on failed processing", %{
      account: account,
      project: project
    } do
      test_run_id = Ecto.UUID.generate()

      expect(Tuist.Accounts, :get_account_by_id, fn _id -> {:ok, account} end)
      expect(Tuist.Storage, :download_to_file, fn _key, _path, _account -> {:ok, :done} end)

      expect(XCResultProcessor, :process_local, fn _path, _opts ->
        {:error, "parse failed"}
      end)

      expect(Tuist.Tests, :create_test, fn _attrs -> {:ok, %{id: test_run_id}} end)
      reject(&Tuist.VCS.enqueue_vcs_pull_request_comment/1)

      vcs_params = %{
        "git_commit_sha" => "abc123",
        "git_ref" => "refs/pull/1/merge",
        "project_id" => project.id
      }

      args =
        test_run_id
        |> job_args(account.id, project.id)
        |> Map.put("vcs_comment_params", vcs_params)

      assert {:error, _} = ProcessXcresultWorker.perform(oban_job(args, 3, 3))
    end
  end
end
