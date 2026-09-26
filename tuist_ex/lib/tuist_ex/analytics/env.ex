defmodule TuistEx.Analytics.Env do
  @moduledoc false

  # Detects the runtime and source-control environment for an analytics
  # submission. Every value is optional on the wire; a missing value stays
  # missing rather than becoming an empty string.

  def elixir_version, do: System.version()

  def otp_version do
    case :erlang.system_info(:otp_release) do
      value when is_list(value) -> List.to_string(value)
      value when is_binary(value) -> value
    end
  end

  def mix_env do
    case Mix.env() do
      value when is_atom(value) -> Atom.to_string(value)
      value -> to_string(value)
    end
  rescue
    # Mix isn't loaded in every context (e.g. release scripts). Skip cleanly.
    _ -> nil
  end

  def ci?(environment \\ &System.get_env/1) do
    truthy?(environment.("CI")) or
      Enum.any?(
        [
          "GITHUB_ACTIONS",
          "GITLAB_CI",
          "CIRCLECI",
          "BITRISE_IO",
          "BUILDKITE",
          "CODEMAGIC_ID"
        ],
        &truthy?(environment.(&1))
      )
  end

  def ci_provider(environment \\ &System.get_env/1) do
    cond do
      truthy?(environment.("GITHUB_ACTIONS")) -> "github"
      truthy?(environment.("GITLAB_CI")) -> "gitlab"
      truthy?(environment.("CIRCLECI")) -> "circleci"
      truthy?(environment.("BITRISE_IO")) -> "bitrise"
      truthy?(environment.("BUILDKITE")) -> "buildkite"
      truthy?(environment.("CODEMAGIC_ID")) -> "codemagic"
      true -> nil
    end
  end

  def ci_run_id(environment \\ &System.get_env/1) do
    case ci_provider(environment) do
      "github" -> environment.("GITHUB_RUN_ID")
      "gitlab" -> environment.("CI_PIPELINE_ID")
      "circleci" -> environment.("CIRCLE_WORKFLOW_ID") || environment.("CIRCLE_BUILD_NUM")
      "bitrise" -> environment.("BITRISE_BUILD_SLUG")
      "buildkite" -> environment.("BUILDKITE_BUILD_ID")
      "codemagic" -> environment.("BUILD_NUMBER")
      _ -> nil
    end
  end

  def ci_project_handle(environment \\ &System.get_env/1) do
    case ci_provider(environment) do
      "github" -> environment.("GITHUB_REPOSITORY")
      "gitlab" -> environment.("CI_PROJECT_PATH")
      "circleci" -> circleci_project_handle(environment)
      "bitrise" -> environment.("BITRISE_APP_SLUG")
      "buildkite" -> environment.("BUILDKITE_PIPELINE_SLUG")
      _ -> nil
    end
  end

  # Origin of the CI provider, primarily useful when a customer runs a
  # self-hosted instance (GitHub Enterprise, self-managed GitLab, or a
  # Buildkite agent behind their own hostname).
  def ci_host(environment \\ &System.get_env/1) do
    case ci_provider(environment) do
      "github" -> environment.("GITHUB_SERVER_URL")
      "gitlab" -> environment.("CI_SERVER_URL")
      "buildkite" -> environment.("BUILDKITE_SERVER_URL")
      _ -> nil
    end
  end

  def git_branch(environment \\ &System.get_env/1),
    do: environment.("GIT_BRANCH") || git("rev-parse", ["--abbrev-ref", "HEAD"])

  def git_commit_sha(environment \\ &System.get_env/1),
    do: environment.("GIT_COMMIT") || git("rev-parse", ["HEAD"])

  def git_ref(environment \\ &System.get_env/1),
    do:
      environment.("GITHUB_REF") || environment.("CI_COMMIT_REF_NAME") ||
        environment.("BUILDKITE_BRANCH") || environment.("CI_COMMIT_REF") || nil

  def git_remote_url_origin(environment \\ &System.get_env/1),
    do:
      environment.("GIT_REMOTE_URL") || environment.("BUILDKITE_REPO") ||
        git("config", ["--get", "remote.origin.url"])

  defp circleci_project_handle(environment) do
    org = environment.("CIRCLE_PROJECT_USERNAME")
    repo = environment.("CIRCLE_PROJECT_REPONAME")

    if is_binary(org) and is_binary(repo) and org != "" and repo != "" do
      org <> "/" <> repo
    end
  end

  defp truthy?(value), do: value not in [nil, "", "0", "false", "FALSE"]

  defp git(subcommand, args) do
    if System.find_executable("git"), do: git_run(subcommand, args)
  end

  defp git_run(subcommand, args) do
    case System.cmd("git", [subcommand | args], stderr_to_stdout: true) do
      {output, 0} -> nilify_empty(String.trim(output))
      _ -> nil
    end
  end

  defp nilify_empty(""), do: nil
  defp nilify_empty(value), do: value
end
