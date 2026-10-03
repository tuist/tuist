defmodule Atlas.Product.Workers.AnnounceReleaseOnIssuesTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.Integrations
  alias Atlas.Integrations.GitHubAPI
  alias Atlas.Product.Workers.AnnounceReleaseOnIssues
  alias Atlas.Repo

  setup :verify_on_exit!

  defp create_github_app do
    {:ok, app} =
      Integrations.create_github_app(%{
        name: "Test Release App " <> Integer.to_string(System.unique_integer([:positive])),
        webhook_secret: "whsec_test",
        app_id: Integer.to_string(System.unique_integer([:positive])),
        private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
        installation_id: Integer.to_string(System.unique_integer([:positive]))
      })

    {:ok, repo} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "tuist"})
    %{app: app, repo: repo}
  end

  describe "pr_numbers/1" do
    test "extracts unique PR numbers referenced by #NNN in the body" do
      body = """
      * feat: something (#42)
      * fix: another (#7)
      * chore: dupe (#42)
      """

      assert AnnounceReleaseOnIssues.pr_numbers(body) == [42, 7]
    end

    test "returns [] for non-strings and empty bodies" do
      assert AnnounceReleaseOnIssues.pr_numbers("") == []
      assert AnnounceReleaseOnIssues.pr_numbers(nil) == []
    end
  end

  describe "perform/1" do
    test "posts a comment on each referenced issue" do
      %{app: app} = create_github_app()

      client = Req.new(base_url: "https://api.github.com")

      expect(GitHubAPI, :req, fn app_arg ->
        assert app_arg.id == app.id
        {:ok, client}
      end)

      release_url = "https://github.com/tuist/tuist/releases/tag/1.2.3"

      expect(Req, :get, fn ^client, opts ->
        assert opts[:url] == "/repos/tuist/tuist/pulls/42"
        {:ok, %Req.Response{status: 200, body: %{"body" => "This closes #100 and fixes #101."}}}
      end)

      expect(Req, :get, fn ^client, opts ->
        assert opts[:url] == "/repos/tuist/tuist/issues/100"
        {:ok, %Req.Response{status: 200, body: %{"number" => 100}}}
      end)

      expect(Req, :get, fn ^client, opts ->
        assert opts[:url] == "/repos/tuist/tuist/issues/101"
        {:ok, %Req.Response{status: 200, body: %{"number" => 101}}}
      end)

      expect(Req, :get, fn ^client, opts ->
        assert opts[:url] == "/repos/tuist/tuist/issues/100/comments"
        {:ok, %Req.Response{status: 200, body: []}}
      end)

      expect(Req, :post, fn ^client, opts ->
        assert opts[:url] == "/repos/tuist/tuist/issues/100/comments"
        assert opts[:json] == %{"body" => "Shipped in [1.2.3](#{release_url})."}
        {:ok, %Req.Response{status: 201, body: %{}}}
      end)

      expect(Req, :get, fn ^client, opts ->
        assert opts[:url] == "/repos/tuist/tuist/issues/101/comments"
        {:ok, %Req.Response{status: 200, body: []}}
      end)

      expect(Req, :post, fn ^client, opts ->
        assert opts[:url] == "/repos/tuist/tuist/issues/101/comments"
        {:ok, %Req.Response{status: 201, body: %{}}}
      end)

      assert :ok =
               perform_job(AnnounceReleaseOnIssues, %{
                 "owner" => "tuist",
                 "repo" => "tuist",
                 "tag" => "1.2.3",
                 "release_url" => release_url,
                 "release_body" => "* feat: something (#42)",
                 "github_app_id" => app.id
               })

      assert Repo.get_by(Activity,
               action: "github.release.issue_announced",
               target_id: "tuist/tuist#100"
             )

      assert Repo.get_by(Activity,
               action: "github.release.issue_announced",
               target_id: "tuist/tuist#101"
             )
    end

    test "skips referenced PRs (not real issues)" do
      %{app: app} = create_github_app()
      client = Req.new(base_url: "https://api.github.com")

      expect(GitHubAPI, :req, fn _ -> {:ok, client} end)

      expect(Req, :get, fn ^client, opts ->
        assert opts[:url] == "/repos/tuist/tuist/pulls/42"
        {:ok, %Req.Response{status: 200, body: %{"body" => "closes #200"}}}
      end)

      expect(Req, :get, fn ^client, opts ->
        assert opts[:url] == "/repos/tuist/tuist/issues/200"

        {:ok,
         %Req.Response{
           status: 200,
           body: %{"number" => 200, "pull_request" => %{"url" => "..."}}
         }}
      end)

      assert :ok =
               perform_job(AnnounceReleaseOnIssues, %{
                 "owner" => "tuist",
                 "repo" => "tuist",
                 "tag" => "1.2.3",
                 "release_url" => "https://example",
                 "release_body" => "(#42)",
                 "github_app_id" => app.id
               })
    end

    test "skips issues that already have a comment linking to the release" do
      %{app: app} = create_github_app()
      client = Req.new(base_url: "https://api.github.com")
      release_url = "https://github.com/tuist/tuist/releases/tag/1.2.3"

      expect(GitHubAPI, :req, fn _ -> {:ok, client} end)

      expect(Req, :get, fn ^client, opts ->
        assert opts[:url] == "/repos/tuist/tuist/pulls/42"
        {:ok, %Req.Response{status: 200, body: %{"body" => "fixes #100"}}}
      end)

      expect(Req, :get, fn ^client, opts ->
        assert opts[:url] == "/repos/tuist/tuist/issues/100"
        {:ok, %Req.Response{status: 200, body: %{"number" => 100}}}
      end)

      expect(Req, :get, fn ^client, opts ->
        assert opts[:url] == "/repos/tuist/tuist/issues/100/comments"

        {:ok,
         %Req.Response{
           status: 200,
           body: [%{"body" => "Shipped in [1.2.3](#{release_url})."}]
         }}
      end)

      # No POST expected — verify_on_exit! catches a stray call.
      assert :ok =
               perform_job(AnnounceReleaseOnIssues, %{
                 "owner" => "tuist",
                 "repo" => "tuist",
                 "tag" => "1.2.3",
                 "release_url" => release_url,
                 "release_body" => "(#42)",
                 "github_app_id" => app.id
               })
    end

    test "returns error when the repository is not configured" do
      assert {:error, :github_repository_not_configured} =
               perform_job(AnnounceReleaseOnIssues, %{
                 "owner" => "unknown",
                 "repo" => "unknown",
                 "tag" => "1.2.3",
                 "release_url" => "https://example",
                 "release_body" => "(#42)",
                 "github_app_id" => Ecto.UUID.generate()
               })
    end
  end
end
