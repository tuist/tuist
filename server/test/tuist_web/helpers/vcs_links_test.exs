defmodule TuistWeb.Helpers.VCSLinksTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Helpers.VCSLinks

  defp project_with_connection(client_url) do
    %{
      vcs_connection: %{
        provider: :github,
        repository_full_handle: "org/repo",
        github_app_installation: %{client_url: client_url}
      }
    }
  end

  describe "commit_link/1" do
    test "links to github.com when the installation targets github.com" do
      assigns = %{project: project_with_connection("https://github.com"), commit_sha: "abc123"}

      html = render_component(&VCSLinks.commit_link/1, assigns)

      assert html =~ ~s(href="https://github.com/org/repo/commit/abc123")
    end

    test "links to the GitHub Enterprise Server host when the installation has a custom client_url" do
      assigns = %{project: project_with_connection("https://github.example.com"), commit_sha: "abc123"}

      html = render_component(&VCSLinks.commit_link/1, assigns)

      assert html =~ ~s(href="https://github.example.com/org/repo/commit/abc123")
      refute html =~ "github.com/org/repo"
    end
  end

  describe "branch_link/1" do
    test "links to github.com when the installation targets github.com" do
      assigns = %{project: project_with_connection("https://github.com"), branch: "main"}

      html = render_component(&VCSLinks.branch_link/1, assigns)

      assert html =~ ~s(href="https://github.com/org/repo/tree/main")
    end

    test "links to the GitHub Enterprise Server host when the installation has a custom client_url" do
      assigns = %{project: project_with_connection("https://github.example.com"), branch: "main"}

      html = render_component(&VCSLinks.branch_link/1, assigns)

      assert html =~ ~s(href="https://github.example.com/org/repo/tree/main")
      refute html =~ "github.com/org/repo"
    end
  end
end
