defmodule TuistWeb.Helpers.FailureMessageTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Helpers.FailureMessage

  defp make_failure(attrs) do
    %{
      path: attrs[:path],
      issue_type: attrs[:issue_type],
      message: attrs[:message],
      line_number: attrs[:line_number] || 42
    }
  end

  defp make_run(attrs \\ %{}) do
    %{
      git_commit_sha: attrs[:git_commit_sha],
      project: %{
        vcs_connection: attrs[:vcs_connection]
      }
    }
  end

  defp github_vcs_connection do
    %{provider: :github, repository_full_handle: "org/repo"}
  end

  describe "format_failure_message/2 without path" do
    test "assertion_failure without message" do
      failure = make_failure(%{path: nil, issue_type: "assertion_failure", message: nil})
      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) == "Expectation failed"
    end

    test "assertion_failure with message" do
      failure = make_failure(%{path: nil, issue_type: "assertion_failure", message: "expected true"})
      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) == "Expectation failed: expected true"
    end

    test "error_thrown without message" do
      failure = make_failure(%{path: nil, issue_type: "error_thrown", message: nil})
      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) == "Caught error"
    end

    test "error_thrown with message" do
      failure = make_failure(%{path: nil, issue_type: "error_thrown", message: "nil reference"})
      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) == "Caught error: nil reference"
    end

    test "issue_recorded without message" do
      failure = make_failure(%{path: nil, issue_type: "issue_recorded", message: nil})
      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) == "Issue recorded"
    end

    test "issue_recorded with message" do
      failure = make_failure(%{path: nil, issue_type: "issue_recorded", message: "known issue"})
      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) == "Issue recorded: known issue"
    end

    test "unknown issue_type without message" do
      failure = make_failure(%{path: nil, issue_type: "other", message: nil})
      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) == "Unknown error"
    end

    test "unknown issue_type with message" do
      failure = make_failure(%{path: nil, issue_type: "other", message: "some error"})
      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) == "some error"
    end

    test "empty string path is treated as nil" do
      failure = make_failure(%{path: "", issue_type: "assertion_failure", message: nil})
      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) == "Expectation failed"
    end
  end

  describe "format_failure_message/2 with path but no GitHub VCS" do
    test "assertion_failure without message" do
      failure = make_failure(%{path: "Tests/MyTest.swift", issue_type: "assertion_failure", message: nil})
      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) ==
               "Expectation failed at Tests/MyTest.swift:42"
    end

    test "assertion_failure with message" do
      failure =
        make_failure(%{path: "Tests/MyTest.swift", issue_type: "assertion_failure", message: "expected true"})

      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) ==
               "Expectation failed at Tests/MyTest.swift:42: expected true"
    end

    test "error_thrown without message" do
      failure = make_failure(%{path: "Tests/MyTest.swift", issue_type: "error_thrown", message: nil})
      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) ==
               "Caught error at Tests/MyTest.swift:42"
    end

    test "error_thrown with message" do
      failure =
        make_failure(%{path: "Tests/MyTest.swift", issue_type: "error_thrown", message: "nil reference"})

      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) ==
               "Caught error at Tests/MyTest.swift:42: nil reference"
    end

    test "issue_recorded without message" do
      failure = make_failure(%{path: "Tests/MyTest.swift", issue_type: "issue_recorded", message: nil})
      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) ==
               "Issue recorded at Tests/MyTest.swift:42"
    end

    test "issue_recorded with message" do
      failure =
        make_failure(%{path: "Tests/MyTest.swift", issue_type: "issue_recorded", message: "known issue"})

      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) ==
               "Issue recorded at Tests/MyTest.swift:42: known issue"
    end

    test "unknown issue_type without message" do
      failure = make_failure(%{path: "Tests/MyTest.swift", issue_type: "other", message: nil})
      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) == "Tests/MyTest.swift:42"
    end

    test "unknown issue_type with message" do
      failure = make_failure(%{path: "Tests/MyTest.swift", issue_type: "other", message: "some error"})
      run = make_run()

      assert FailureMessage.format_failure_message(failure, run) == "Tests/MyTest.swift:42: some error"
    end
  end

  describe "format_failure_message/2 with path and GitHub VCS" do
    test "links to GitHub when provider is github and commit sha is present" do
      failure =
        make_failure(%{
          path: "Tests/MyTest.swift",
          issue_type: "assertion_failure",
          message: nil,
          line_number: 100
        })

      run = make_run(%{git_commit_sha: "abc123", vcs_connection: github_vcs_connection()})

      {:safe, html} = FailureMessage.format_failure_message(failure, run)

      assert html =~ ~s(href="https://github.com/org/repo/blob/abc123/Tests/MyTest.swift#L100")
      assert html =~ "Tests/MyTest.swift:100"
      assert html =~ "Expectation failed at"
    end

    test "does not link when git_commit_sha is nil" do
      failure = make_failure(%{path: "Tests/MyTest.swift", issue_type: "assertion_failure", message: nil})
      run = make_run(%{git_commit_sha: nil, vcs_connection: github_vcs_connection()})

      result = FailureMessage.format_failure_message(failure, run)

      assert is_binary(result)
      assert result == "Expectation failed at Tests/MyTest.swift:42"
    end

    test "does not link when provider is not github" do
      failure = make_failure(%{path: "Tests/MyTest.swift", issue_type: "assertion_failure", message: nil})

      run =
        make_run(%{
          git_commit_sha: "abc123",
          vcs_connection: %{provider: :gitlab, repository_full_handle: "org/repo"}
        })

      result = FailureMessage.format_failure_message(failure, run)

      assert is_binary(result)
      assert result == "Expectation failed at Tests/MyTest.swift:42"
    end

    test "does not link when vcs_connection is nil" do
      failure = make_failure(%{path: "Tests/MyTest.swift", issue_type: "assertion_failure", message: nil})
      run = make_run(%{git_commit_sha: "abc123", vcs_connection: nil})

      result = FailureMessage.format_failure_message(failure, run)

      assert is_binary(result)
      assert result == "Expectation failed at Tests/MyTest.swift:42"
    end
  end
end
