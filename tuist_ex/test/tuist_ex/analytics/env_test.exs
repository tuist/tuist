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

  test "detects the CI host for self-hosted providers" do
    for {provider, host_var, host} <- [
          {"github", "GITHUB_SERVER_URL", "https://github.acme.example"},
          {"gitlab", "CI_SERVER_URL", "https://gitlab.acme.example"},
          {"buildkite", "BUILDKITE_SERVER_URL", "https://buildkite.acme.example"}
        ] do
      environment = fn key ->
        cond do
          key == provider_env_var(provider) -> "true"
          key == host_var -> host
          true -> nil
        end
      end

      assert Env.ci_host(environment) == host
    end
  end

  defp provider_env_var("github"), do: "GITHUB_ACTIONS"
  defp provider_env_var("gitlab"), do: "GITLAB_CI"
  defp provider_env_var("buildkite"), do: "BUILDKITE"

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

  test "takes the branch from the CI provider before git" do
    # A GitHub Actions pull request is a detached checkout, where git says "HEAD".
    assert Env.git_branch(&%{"GITHUB_HEAD_REF" => "feature/x"}[&1]) == "feature/x"
    assert Env.git_branch(&%{"CI_COMMIT_REF_NAME" => "main"}[&1]) == "main"

    assert Env.git_branch(&%{"GITHUB_REF_TYPE" => "branch", "GITHUB_REF_NAME" => "main"}[&1]) ==
             "main"
  end

  test "does not take a GitHub tag push for a branch" do
    refute Env.git_branch(&%{"GITHUB_REF_TYPE" => "tag", "GITHUB_REF_NAME" => "v1.0.0"}[&1]) ==
             "v1.0.0"
  end

  test "never reports credentials embedded in the git remote" do
    environment = fn
      "GIT_REMOTE_URL" -> "https://x-access-token:secret-token@github.com/acme/private.git"
      _ -> nil
    end

    assert Env.git_remote_url_origin(environment) == "https://github.com/acme/private.git"

    # Remotes without credentials, and the forms that are not web addresses, are left as they are.
    assert Env.without_credentials("https://github.com/acme/private.git") ==
             "https://github.com/acme/private.git"

    assert Env.without_credentials("git@github.com:acme/private.git") ==
             "git@github.com:acme/private.git"

    assert Env.without_credentials(nil) == nil
  end

  test "reads the base branch from the CI provider, without a full ref's prefix" do
    assert Env.base_branch(fn
             "GITHUB_BASE_REF" -> "main"
             _ -> nil
           end) == "main"

    assert Env.base_branch(fn
             "SYSTEM_PULLREQUEST_TARGETBRANCH" -> "refs/heads/develop"
             _ -> nil
           end) == "develop"

    assert Env.base_branch(fn _ -> nil end) == nil
  end

  test "reads the pull request number from the ref, then the provider's variables" do
    assert Env.pull_request_number(fn
             "GITHUB_REF" -> "refs/pull/42/merge"
             _ -> nil
           end) == 42

    assert Env.pull_request_number(fn
             "CI_MERGE_REQUEST_IID" -> "7"
             _ -> nil
           end) == 7

    assert Env.pull_request_number(fn
             "GITHUB_REF" -> "refs/heads/main"
             _ -> nil
           end) == nil

    assert Env.pull_request_number(fn
             "BITRISE_PULL_REQUEST" -> "false"
             _ -> nil
           end) == nil
  end
end
