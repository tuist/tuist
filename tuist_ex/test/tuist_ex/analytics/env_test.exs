defmodule TuistEx.Analytics.EnvTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.Env

  test "elixir_version returns the runtime version" do
    assert Env.elixir_version() == System.version()
  end

  test "otp_version returns a binary" do
    assert is_binary(Env.otp_version())
  end

  test "ci? returns true for a CI environment" do
    environment = fn
      "CI" -> "true"
      _ -> nil
    end

    assert Env.ci?(environment)
  end

  test "ci? returns false when nothing indicates CI" do
    refute Env.ci?(fn _ -> nil end)
  end

  test "detects the GitHub Actions provider and run id" do
    environment = fn
      "GITHUB_ACTIONS" -> "true"
      "GITHUB_RUN_ID" -> "12345"
      "GITHUB_REPOSITORY" -> "tuist/tuist"
      _ -> nil
    end

    assert Env.ci_provider(environment) == "github"
    assert Env.ci_run_id(environment) == "12345"
    assert Env.ci_project_handle(environment) == "tuist/tuist"
  end

  test "detects the CircleCI provider with a composed project handle" do
    environment = fn
      "CIRCLECI" -> "true"
      "CIRCLE_PROJECT_USERNAME" -> "acme"
      "CIRCLE_PROJECT_REPONAME" -> "widgets"
      "CIRCLE_WORKFLOW_ID" -> "abc-123"
      _ -> nil
    end

    assert Env.ci_provider(environment) == "circleci"
    assert Env.ci_project_handle(environment) == "acme/widgets"
    assert Env.ci_run_id(environment) == "abc-123"
  end

  test "prefers explicit git env overrides over shelling out" do
    environment = fn
      "GIT_BRANCH" -> "main"
      "GIT_COMMIT" -> "deadbeef"
      "GIT_REMOTE_URL" -> "git@github.com:tuist/tuist.git"
      _ -> nil
    end

    assert Env.git_branch(environment) == "main"
    assert Env.git_commit_sha(environment) == "deadbeef"
    assert Env.git_remote_url_origin(environment) == "git@github.com:tuist/tuist.git"
  end
end
