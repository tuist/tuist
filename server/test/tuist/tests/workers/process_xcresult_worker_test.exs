defmodule Tuist.Tests.Workers.ProcessXcresultWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Tests.Workers.ProcessXcresultWorker

  setup :verify_on_exit!

  @storage_key "tuist/tests/test-xcresult.zip"
  @test_run_id Ecto.UUID.generate()

  setup do
    %{account: account} =
      TuistTestSupport.Fixtures.AccountsFixtures.user_fixture(preload: [:account])

    project = TuistTestSupport.Fixtures.ProjectsFixtures.project_fixture()

    %{account: account, project: project}
  end

  defp job_args(test_run_id, account_id, project_id, opts \\ []) do
    %{
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

  describe "perform/1 when xcode_processor_url is not configured (local processing)" do
    setup do
      stub(Tuist.Environment, :xcode_processor_url, fn -> nil end)
      :ok
    end

    test "processes locally when url is nil", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()

      expect(Tuist.Accounts, :get_account_by_id, fn id ->
        assert id == account.id
        {:ok, account}
      end)

      expect(Tuist.Storage, :download_to_file, fn _key, _path, _account ->
        {:ok, :done}
      end)

      expect(XcodeProcessor.XCResultProcessor, :process_local, fn _path, _opts ->
        {:ok, parsed_data()}
      end)

      expect(Tuist.Tests, :create_test, fn _attrs -> {:ok, %{id: test_run_id}} end)

      assert :ok ==
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id)))
    end

    test "processes locally when url is empty string", %{account: account, project: project} do
      stub(Tuist.Environment, :xcode_processor_url, fn -> "" end)
      test_run_id = Ecto.UUID.generate()

      expect(Tuist.Accounts, :get_account_by_id, fn _id -> {:ok, account} end)
      expect(Tuist.Storage, :download_to_file, fn _key, _path, _account -> {:ok, :done} end)
      expect(XcodeProcessor.XCResultProcessor, :process_local, fn _path, _opts -> {:ok, parsed_data()} end)
      expect(Tuist.Tests, :create_test, fn _attrs -> {:ok, %{id: test_run_id}} end)

      assert :ok ==
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id)))
    end
  end

  describe "perform/1 when webhook_secret is not configured" do
    setup do
      stub(Tuist.Environment, :xcode_processor_url, fn -> "http://localhost:4003" end)
      stub(Tuist.Environment, :xcode_processor_webhook_secret, fn -> nil end)
      :ok
    end

    test "returns error when webhook_secret is nil", %{account: account, project: project} do
      assert {:error, "webhook_secret_not_configured"} =
               ProcessXcresultWorker.perform(oban_job(job_args(@test_run_id, account.id, project.id)))
    end

    test "returns error when webhook_secret is empty string", %{account: account, project: project} do
      stub(Tuist.Environment, :xcode_processor_webhook_secret, fn -> "" end)

      assert {:error, "webhook_secret_not_configured"} =
               ProcessXcresultWorker.perform(oban_job(job_args(@test_run_id, account.id, project.id)))
    end
  end

  describe "perform/1 with xcode_processor_url configured" do
    setup do
      stub(Tuist.Environment, :xcode_processor_url, fn -> "http://localhost:4003" end)
      stub(Tuist.Environment, :xcode_processor_webhook_secret, fn -> "test-secret" end)
      :ok
    end

    test "sends xcresult to processor and creates test from parsed data", %{
      account: account,
      project: project
    } do
      test_run_id = Ecto.UUID.generate()

      expect(Req, :post, fn url, opts ->
        assert url == "http://localhost:4003/webhooks/process-xcresult"
        body = Jason.decode!(opts[:body])
        assert body["test_run_id"] == test_run_id
        assert body["storage_key"] == @storage_key
        assert body["account_id"] == account.id
        assert body["project_id"] == project.id
        assert Enum.any?(opts[:headers], fn {k, _v} -> k == "x-webhook-signature" end)
        {:ok, %{status: 200, body: parsed_data()}}
      end)

      expect(Tuist.Tests, :create_test, fn attrs ->
        assert attrs.id == test_run_id
        assert attrs.project_id == project.id
        assert attrs.account_id == account.id
        assert attrs.test_plan_name == "AppTests"
        assert attrs.status == "success"
        assert attrs.duration == 45.2
        assert attrs.is_ci == false
        assert attrs.git_branch == "main"
        assert attrs.git_commit_sha == "abc123"
        assert attrs.xcode_version == "16.0"
        assert attrs.macos_version == "15.0"
        assert attrs.scheme == "App"
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

    test "normalizes 'passed' status to 'success'", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()

      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: parsed_data()}}
      end)

      expect(Tuist.Tests, :create_test, fn attrs ->
        assert attrs.status == "success"

        [module] = attrs.test_modules
        assert module["status"] == "success"

        [suite] = module["test_suites"]
        assert suite["status"] == "success"

        [test_case] = module["test_cases"]
        assert test_case["status"] == "success"

        {:ok, %{id: test_run_id}}
      end)

      assert :ok ==
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id)))
    end

    test "normalizes 'failed' status to 'failure'", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()

      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 200, body: parsed_data_with_failure()}}
      end)

      expect(Tuist.Tests, :create_test, fn attrs ->
        assert attrs.status == "failure"

        [module] = attrs.test_modules
        assert module["status"] == "failure"

        [suite] = module["test_suites"]
        assert suite["status"] == "failure"

        [test_case] = module["test_cases"]
        assert test_case["status"] == "failure"
        assert length(test_case["failures"]) == 1

        [failure] = test_case["failures"]
        assert failure["message"] == "XCTAssertTrue failed"
        assert failure["path"] == "AppTests/AppTests.swift"
        assert failure["line_number"] == 42
        assert failure["issue_type"] == "assertion_failure"

        {:ok, %{id: test_run_id}}
      end)

      assert :ok ==
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id)))
    end

    test "signs webhook request with HMAC-SHA256", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()

      expect(Req, :post, fn _url, opts ->
        body = opts[:body]
        {_, signature} = Enum.find(opts[:headers], fn {k, _v} -> k == "x-webhook-signature" end)

        expected_signature =
          :hmac
          |> :crypto.mac(:sha256, "test-secret", body)
          |> Base.encode16(case: :lower)

        assert signature == expected_signature
        {:ok, %{status: 200, body: parsed_data()}}
      end)

      expect(Tuist.Tests, :create_test, fn _attrs -> {:ok, %{id: test_run_id}} end)

      assert :ok ==
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id)))
    end

    test "returns error when processor returns non-200", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()

      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 500, body: %{"error" => "internal error"}}}
      end)

      assert {:error, _} =
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id), 1, 3))
    end

    test "returns error when HTTP request fails", %{account: account, project: project} do
      test_run_id = Ecto.UUID.generate()

      expect(Req, :post, fn _url, _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} =
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id), 1, 3))
    end

    test "marks test run as failed_processing on max attempts when processor returns non-200", %{
      account: account,
      project: project
    } do
      test_run_id = Ecto.UUID.generate()

      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 500, body: %{"error" => "internal error"}}}
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

    test "marks test run as failed_processing on max attempts when HTTP request fails", %{
      account: account,
      project: project
    } do
      test_run_id = Ecto.UUID.generate()

      expect(Req, :post, fn _url, _opts ->
        {:error, :closed}
      end)

      expect(Tuist.Tests, :create_test, fn attrs ->
        assert attrs.id == test_run_id
        assert attrs.status == "failed_processing"
        assert attrs.duration == 0
        assert attrs.test_modules == []
        {:ok, %{id: test_run_id}}
      end)

      assert {:error, :closed} =
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id), 3, 3))
    end

    test "does not mark as failed_processing on non-final attempt", %{
      account: account,
      project: project
    } do
      test_run_id = Ecto.UUID.generate()

      expect(Req, :post, fn _url, _opts ->
        {:ok, %{status: 500, body: %{"error" => "internal error"}}}
      end)

      assert {:error, _} =
               ProcessXcresultWorker.perform(oban_job(job_args(test_run_id, account.id, project.id), 1, 3))
    end
  end
end
