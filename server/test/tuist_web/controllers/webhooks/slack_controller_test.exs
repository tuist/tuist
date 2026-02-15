defmodule TuistWeb.Webhooks.SlackControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Slack.Client
  alias TuistTestSupport.Fixtures.SlackFixtures
  alias TuistWeb.Webhooks.SlackController

  describe "handle/2 with link_shared event" do
    test "unfurls a valid build-run URL", %{conn: conn} do
      installation = SlackFixtures.slack_installation_fixture(team_id: "T12345")

      build = %Tuist.Builds.Build{
        id: "06a2b6e4-1234-5678-9abc-def012345678",
        scheme: "MyApp",
        status: "success",
        duration: 125_000,
        git_branch: "main",
        git_commit_sha: "abc1234567890",
        is_ci: true,
        ci_provider: "github",
        category: "clean",
        project_id: 1
      }

      build_with_project = %{
        build
        | project: %Tuist.Projects.Project{
            id: 1,
            account: %Tuist.Accounts.Account{id: installation.account_id}
          }
      }

      stub(Tuist.Builds, :get_build, fn "06a2b6e4-1234-5678-9abc-def012345678" -> build end)
      stub(Tuist.Repo, :preload, fn ^build, [project: :account] -> build_with_project end)

      expect(Client, :unfurl, fn token, channel, ts, unfurls ->
        assert token == installation.access_token
        assert channel == "C12345"
        assert ts == "1234567890.123456"

        assert Map.has_key?(
                 unfurls,
                 "https://tuist.dev/tuist/tuist/builds/build-runs/06a2b6e4-1234-5678-9abc-def012345678"
               )

        :ok
      end)

      params = %{
        "team_id" => "T12345",
        "event" => %{
          "type" => "link_shared",
          "channel" => "C12345",
          "message_ts" => "1234567890.123456",
          "links" => [
            %{
              "url" =>
                "https://tuist.dev/tuist/tuist/builds/build-runs/06a2b6e4-1234-5678-9abc-def012345678"
            }
          ]
        }
      }

      result = SlackController.handle(conn, params)

      assert result.status == 200
    end

    test "skips non-matching URLs", %{conn: conn} do
      SlackFixtures.slack_installation_fixture(team_id: "T12345")

      reject(Client, :unfurl, 4)

      params = %{
        "team_id" => "T12345",
        "event" => %{
          "type" => "link_shared",
          "channel" => "C12345",
          "message_ts" => "1234567890.123456",
          "links" => [
            %{"url" => "https://tuist.dev/tuist/tuist/previews/some-id"}
          ]
        }
      }

      result = SlackController.handle(conn, params)

      assert result.status == 200
    end

    test "returns OK when installation is not found", %{conn: conn} do
      reject(Client, :unfurl, 4)

      params = %{
        "team_id" => "T_UNKNOWN",
        "event" => %{
          "type" => "link_shared",
          "channel" => "C12345",
          "message_ts" => "1234567890.123456",
          "links" => [
            %{"url" => "https://tuist.dev/tuist/tuist/builds/build-runs/some-id"}
          ]
        }
      }

      result = SlackController.handle(conn, params)

      assert result.status == 200
    end

    test "skips when build is not found", %{conn: conn} do
      SlackFixtures.slack_installation_fixture(team_id: "T12345")

      stub(Tuist.Builds, :get_build, fn _ -> nil end)
      reject(Client, :unfurl, 4)

      params = %{
        "team_id" => "T12345",
        "event" => %{
          "type" => "link_shared",
          "channel" => "C12345",
          "message_ts" => "1234567890.123456",
          "links" => [
            %{"url" => "https://tuist.dev/tuist/tuist/builds/build-runs/nonexistent-id"}
          ]
        }
      }

      result = SlackController.handle(conn, params)

      assert result.status == 200
    end

    test "skips unfurling when build belongs to a different account", %{conn: conn} do
      SlackFixtures.slack_installation_fixture(team_id: "T12345")

      build = %Tuist.Builds.Build{
        id: "06a2b6e4-1234-5678-9abc-def012345678",
        scheme: "MyApp",
        status: "success",
        duration: 125_000,
        git_branch: "main",
        git_commit_sha: "abc1234567890",
        is_ci: true,
        ci_provider: "github",
        category: "clean",
        project_id: 1
      }

      build_with_different_account = %{
        build
        | project: %Tuist.Projects.Project{
            id: 1,
            account: %Tuist.Accounts.Account{id: 999_999}
          }
      }

      stub(Tuist.Builds, :get_build, fn "06a2b6e4-1234-5678-9abc-def012345678" -> build end)

      stub(Tuist.Repo, :preload, fn ^build, [project: :account] ->
        build_with_different_account
      end)

      reject(Client, :unfurl, 4)

      params = %{
        "team_id" => "T12345",
        "event" => %{
          "type" => "link_shared",
          "channel" => "C12345",
          "message_ts" => "1234567890.123456",
          "links" => [
            %{
              "url" =>
                "https://tuist.dev/tuist/tuist/builds/build-runs/06a2b6e4-1234-5678-9abc-def012345678"
            }
          ]
        }
      }

      result = SlackController.handle(conn, params)

      assert result.status == 200
    end
  end

  describe "handle/2 with unknown event" do
    test "returns OK", %{conn: conn} do
      params = %{
        "team_id" => "T12345",
        "event" => %{
          "type" => "some_unknown_event"
        }
      }

      result = SlackController.handle(conn, params)

      assert result.status == 200
    end
  end
end
