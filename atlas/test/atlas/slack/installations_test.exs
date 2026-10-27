defmodule Atlas.Slack.InstallationsTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.Repo
  alias Atlas.Slack.Installation
  alias Atlas.Slack.Installations
  alias Atlas.Users.User

  setup :verify_on_exit!

  @config %{
    client_id: "client-id",
    client_secret: "client-secret",
    signing_secret: "signing-secret",
    scopes: ["chat:write"]
  }

  describe "authorize_url/3" do
    test "builds the Slack authorize URL with scopes joined by comma" do
      assert {:ok, url} =
               Installations.authorize_url(
                 "https://atlas.example/slack/install/callback",
                 "state-1",
                 @config
               )

      assert url =~ "https://slack.com/oauth/v2/authorize?"
      assert url =~ "client_id=client-id"
      assert url =~ "scope=chat%3Awrite"
      assert url =~ "state=state-1"
      assert url =~ "redirect_uri=https%3A%2F%2Fatlas.example%2Fslack%2Finstall%2Fcallback"
    end

    test "passes a team hint when exactly one workspace is allowed" do
      config = Map.put(@config, :allowed_team_ids, ["T-company"])

      assert {:ok, url} =
               Installations.authorize_url(
                 "https://atlas.example/slack/install/callback",
                 "state-1",
                 config
               )

      assert url =~ "team=T-company"
    end
  end

  describe "complete_install/3" do
    test "exchanges the code and stores the company installation" do
      stub(Req, :post, fn url, opts ->
        assert url == "https://slack.com/api/oauth.v2.access"
        assert {:basic, "client-id:client-secret"} = Keyword.fetch!(opts, :auth)
        body = Keyword.fetch!(opts, :body)
        assert body =~ "code=auth-code"
        assert body =~ "redirect_uri=https%3A%2F%2Fatlas.example%2Fslack%2Finstall%2Fcallback"

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "access_token" => "xoxb-fresh",
             "scope" => "chat:write,app_mentions:read",
             "bot_user_id" => "U-bot",
             "team" => %{"id" => "T-company", "name" => "Company"}
           }
         }}
      end)

      assert {:ok, %Installation{} = installation} =
               Installations.complete_install(
                 "auth-code",
                 "https://atlas.example/slack/install/callback",
                 config: @config
               )

      assert installation.app_key == :company
      assert installation.team_id == "T-company"
      assert installation.team_name == "Company"
      assert installation.bot_token == "xoxb-fresh"
      assert installation.bot_user_id == "U-bot"
      assert Installation.connected?(installation)
    end

    test "upserts the single company installation when the workspace reinstalls" do
      stub(Req, :post, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "access_token" => "xoxb-second",
             "team" => %{"id" => "T-company", "name" => "Company renamed"}
           }
         }}
      end)

      {:ok, first} =
        Installations.complete_install("code-1", "https://atlas.example/slack/install/callback", config: @config)

      {:ok, second} =
        Installations.complete_install("code-2", "https://atlas.example/slack/install/callback", config: @config)

      assert second.id == first.id
      assert second.app_key == :company
      assert second.team_name == "Company renamed"
      assert second.bot_token == "xoxb-second"
    end

    test "rejects workspaces outside the allowlist" do
      stub(Req, :post, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "access_token" => "xoxb-fresh",
             "team" => %{"id" => "T-other", "name" => "Other"}
           }
         }}
      end)

      config = Map.put(@config, :allowed_team_ids, ["T-company"])

      assert {:error, :workspace_not_allowed} =
               Installations.complete_install("code", "https://atlas.example", config: config)
    end

    test "returns an error instead of crashing when Slack omits the team id" do
      stub(Req, :post, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "access_token" => "xoxb-fresh",
             "scope" => "chat:write"
           }
         }}
      end)

      assert {:error, :missing_team_id} =
               Installations.complete_install("code", "https://atlas.example", config: @config)
    end

    test "records the connection audit trail against the executive who installed" do
      user = insert_user!(%{email: "installer@example.com", role: :executive})

      stub(Req, :post, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "access_token" => "xoxb-fresh",
             "team" => %{"id" => "T-company", "name" => "Company"}
           }
         }}
      end)

      assert {:ok, %Installation{}} =
               Installations.complete_install(
                 "code",
                 "https://atlas.example",
                 config: @config,
                 actor: user
               )

      activity = Repo.get_by!(Activity, action: "slack.installation.connected")
      assert activity.interface == "dashboard"
      assert activity.actor_id == user.id
      assert activity.actor_email == "installer@example.com"
    end
  end

  defp insert_user!(attrs) do
    defaults = %{
      email: "user-#{System.unique_integer([:positive])}@tuist.dev",
      name: "Test User",
      role: :employee
    }

    %User{}
    |> User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
