defmodule TuistWeb.Runs.PullRequestButtonTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Runs.PullRequestButton

  @project %{
    vcs_connection: %{
      provider: :github,
      repository_full_handle: "org/repo",
      github_app_installation: %{client_url: "https://github.example.com"}
    }
  }

  test "links to the pull request" do
    html =
      render_component(&PullRequestButton.pull_request_button/1,
        project: @project,
        git_ref: "refs/pull/42/merge"
      )

    assert html =~ ~s(href="https://github.example.com/org/repo/pull/42")
    assert html =~ "PR #42"
  end

  test "renders a disabled button without a link" do
    html =
      render_component(&PullRequestButton.pull_request_button/1,
        project: @project,
        git_ref: "refs/pull/42/merge",
        disabled: true
      )

    assert html =~ "PR #42"
    assert html =~ "disabled"
    refute html =~ "href="
  end

  test "renders nothing when the git ref is not a pull request ref" do
    html =
      render_component(&PullRequestButton.pull_request_button/1,
        project: @project,
        git_ref: "refs/heads/main"
      )

    refute html =~ "PR #"
  end

  test "renders nothing when the project has no version control connection" do
    html =
      render_component(&PullRequestButton.pull_request_button/1,
        project: %{vcs_connection: nil},
        git_ref: "refs/pull/42/merge"
      )

    refute html =~ "PR #"
  end
end
