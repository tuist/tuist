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

  # The variables CI providers name the branch in, in the CLI's order. A pull
  # request on GitHub Actions is a detached checkout of its merge commit, where
  # git can only answer "HEAD".
  @branch_variables ~w(GIT_BRANCH GITHUB_HEAD_REF CI_COMMIT_REF_NAME BITRISE_GIT_BRANCH
                       CIRCLE_BRANCH BUILDKITE_BRANCH CM_BRANCH AC_GIT_BRANCH CI_BRANCH
                       teamcity.build.branch BUILD_SOURCEBRANCHNAME)

  def git_branch(environment \\ &System.get_env/1) do
    Enum.find_value(@branch_variables, &nilify_empty(environment.(&1) || "")) ||
      github_branch(environment) ||
      case git("rev-parse", ["--abbrev-ref", "HEAD"]) do
        "HEAD" -> nil
        branch -> branch
      end
  end

  # For the events `GITHUB_HEAD_REF` does not cover, such as a push. On a tag
  # push `GITHUB_REF_NAME` names the tag, which is not a branch.
  defp github_branch(environment) do
    if environment.("GITHUB_REF_TYPE") == "branch",
      do: nilify_empty(environment.("GITHUB_REF_NAME") || "")
  end

  def git_commit_sha(environment \\ &System.get_env/1),
    do: environment.("GIT_COMMIT") || git("rev-parse", ["HEAD"])

  def git_ref(environment \\ &System.get_env/1),
    do:
      environment.("GITHUB_REF") || environment.("CI_COMMIT_REF_NAME") ||
        environment.("BUILDKITE_BRANCH") || environment.("CI_COMMIT_REF") || nil

  # The branch a pull request merges into, from the CI provider only: a
  # checkout does not know what its commit will merge into. Azure DevOps names
  # it as a full ref.
  @base_branch_variables ~w(GITHUB_BASE_REF CI_MERGE_REQUEST_TARGET_BRANCH_NAME
                            CI_EXTERNAL_PULL_REQUEST_TARGET_BRANCH_NAME BITRISEIO_GIT_BRANCH_DEST
                            BUILDKITE_PULL_REQUEST_BASE_BRANCH CM_PULL_REQUEST_DEST
                            CI_PULL_REQUEST_TARGET_BRANCH SYSTEM_PULLREQUEST_TARGETBRANCH)

  def base_branch(environment \\ &System.get_env/1) do
    case Enum.find_value(@base_branch_variables, &nilify_empty(environment.(&1) || "")) do
      "refs/heads/" <> branch -> branch
      branch -> branch
    end
  end

  @pull_request_variables ~w(CM_PULL_REQUEST_NUMBER CI_EXTERNAL_PULL_REQUEST_IID BITRISE_PULL_REQUEST
                             AC_PULL_NUMBER CI_PULL_REQUEST_NUMBER BUILDKITE_PULL_REQUEST
                             CIRCLE_PR_NUMBER CI_MERGE_REQUEST_IID)

  def pull_request_number(environment \\ &System.get_env/1) do
    from_ref =
      case Regex.run(~r{^refs/(?:pull|merge-requests)/(\d+)/}, git_ref(environment) || "") do
        [_, number] -> number
        nil -> nil
      end

    (from_ref || Enum.find_value(@pull_request_variables, &nilify_empty(environment.(&1) || "")))
    |> parse_pull_request_number()
  end

  defp parse_pull_request_number(nil), do: nil

  defp parse_pull_request_number(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> nil
    end
  end

  def git_remote_url_origin(environment \\ &System.get_env/1) do
    without_credentials(
      environment.("GIT_REMOTE_URL") || environment.("BUILDKITE_REPO") ||
        git("config", ["--get", "remote.origin.url"])
    )
  end

  # A remote can carry a token (`https://user:token@host/repo.git`), which
  # identifies nothing about the repository and must not leave the machine.
  @doc false
  def without_credentials(remote) when is_binary(remote) do
    case URI.parse(remote) do
      %URI{scheme: scheme, userinfo: userinfo, host: host} = uri
      when scheme in ["http", "https"] and is_binary(userinfo) and is_binary(host) ->
        URI.to_string(%{uri | userinfo: nil, authority: nil})

      _ ->
        remote
    end
  end

  def without_credentials(remote), do: remote

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
