defmodule Atlas.Integrations.GitHubEventsTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Integrations.GitHubEvents
  alias Atlas.Product.Workers.AnnounceReleaseOnIssues
  alias Atlas.Product.Workers.IngestGitHubEvent

  describe "verify_signature/3" do
    test "returns :ok for valid signature" do
      body = ~s({"action":"opened"})
      secret = "test_secret"

      expected =
        "sha256=" <>
          (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))

      assert :ok = GitHubEvents.verify_signature(body, expected, secret)
    end

    test "returns error for invalid signature" do
      assert {:error, :invalid_signature} =
               GitHubEvents.verify_signature("body", "sha256=wrong", "secret")
    end
  end

  describe "handle_event/2" do
    test "enqueues supported product events and ignores unrelated events" do
      payload = %{
        "action" => "opened",
        "repository" => %{"name" => "atlas", "owner" => %{"login" => "tuist"}},
        "issue" => %{"id" => 1, "number" => 2}
      }

      github_app_id = Ecto.UUID.generate()
      assert {:ok, _job} = GitHubEvents.handle_event("issues", payload, github_app_id: github_app_id)

      assert_enqueued(
        worker: IngestGitHubEvent,
        args: %{"event_type" => "issues", "github_app_id" => github_app_id}
      )

      assert :ignored = GitHubEvents.handle_event("push", %{})
    end

    test "enqueues a release announcement job for published releases" do
      github_app_id = Ecto.UUID.generate()

      payload = %{
        "action" => "published",
        "repository" => %{"name" => "tuist", "owner" => %{"login" => "tuist"}},
        "release" => %{
          "tag_name" => "1.2.3",
          "html_url" => "https://github.com/tuist/tuist/releases/tag/1.2.3",
          "body" => "* fix: something (#42)"
        }
      }

      assert {:ok, _job} = GitHubEvents.handle_event("release", payload, github_app_id: github_app_id)

      assert_enqueued(
        worker: AnnounceReleaseOnIssues,
        args: %{
          "owner" => "tuist",
          "repo" => "tuist",
          "tag" => "1.2.3",
          "github_app_id" => github_app_id
        }
      )
    end

    test "ignores non-published release actions" do
      payload = %{
        "action" => "created",
        "repository" => %{"name" => "tuist", "owner" => %{"login" => "tuist"}},
        "release" => %{"tag_name" => "1.2.3", "html_url" => "https://example"}
      }

      assert :ignored = GitHubEvents.handle_event("release", payload)
    end
  end
end
