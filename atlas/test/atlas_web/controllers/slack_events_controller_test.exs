defmodule AtlasWeb.SlackEventsControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.GTM
  alias Atlas.GTM.Opportunity
  alias Atlas.Repo
  alias Atlas.Slack
  alias Atlas.Slack.API
  alias Atlas.Slack.Bot
  alias Atlas.Slack.Installation
  alias Atlas.Slack.Workers.RespondToConversation

  setup :verify_on_exit!

  setup do
    Bot
    |> stub(:signing_secret, fn -> "company-secret" end)

    Bot
    |> stub(:configured?, fn
      :company -> true
      _app_key -> false
    end)

    API
    |> stub(:get_user_info, fn _app_key, user_id ->
      {:ok,
       %{
         slack_user_id: user_id,
         name: "customer",
         display_name: "customer",
         is_bot: false,
         is_external: true
       }}
    end)

    API
    |> stub(:get_permalink, fn _app_key, channel_id, ts ->
      {:ok, "https://community.slack.com/archives/#{channel_id}/p#{String.replace(ts, ".", "")}"}
    end)

    :ok
  end

  describe "POST /api/slack/events" do
    test "routes an installed workspace event through the company Slack app", %{conn: conn} do
      account = insert_account!()

      insert_slack_installation!("T_COMPANY")

      {:ok, _channel} =
        Slack.add_channel(%{
          slack_app: :company,
          channel_id: "C_COMPANY",
          channel_name: "company-customer",
          account_id: account.id
        })

      payload = %{
        "type" => "event_callback",
        "team_id" => "T_COMPANY",
        "event" => %{
          "type" => "message",
          "channel" => "C_COMPANY",
          "user" => "U_CUSTOMER",
          "text" => "Question from the company workspace",
          "ts" => "1710000200.100000"
        }
      }

      conn = post_signed(conn, payload, "company-secret")

      assert json_response(conn, 200) == %{"ok" => true}

      event = Repo.get_by!(Event, external_id: "slack:company:C_COMPANY:1710000200.100000")
      assert event.account_id == account.id
      assert event.metadata["slack_app"] == "company"
      assert event.metadata["channel_name"] == "company-customer"
    end

    test "records a signed event for a workspace that has not completed the install", %{conn: conn} do
      # No installation row and no bot token: the request is still authentic
      # (signature verified), so the message must be captured on the timeline.
      Bot
      |> stub(:configured?, fn _app_key -> false end)

      account = insert_account!()

      {:ok, _channel} =
        Slack.add_channel(%{
          slack_app: :company,
          channel_id: "C_LEGACY",
          channel_name: "legacy-customer",
          account_id: account.id
        })

      payload = %{
        "type" => "event_callback",
        "team_id" => "T_UNINSTALLED",
        "event" => %{
          "type" => "message",
          "channel" => "C_LEGACY",
          "user" => "U_CUSTOMER",
          "text" => "Still tracked without an install",
          "ts" => "1710000205.100000"
        }
      }

      conn = post_signed(conn, payload, "company-secret")

      assert json_response(conn, 200) == %{"ok" => true}

      event = Repo.get_by!(Event, external_id: "slack:company:C_LEGACY:1710000205.100000")
      assert event.account_id == account.id
    end

    test "ignores an uninstalled team outside the configured allowlist", %{conn: conn} do
      Bot
      |> stub(:allowed_team_ids, fn -> ["T_COMPANY"] end)

      account = insert_account!()

      {:ok, _channel} =
        Slack.add_channel(%{
          slack_app: :company,
          channel_id: "C_FOREIGN",
          channel_name: "foreign-customer",
          account_id: account.id
        })

      payload = %{
        "type" => "event_callback",
        "team_id" => "T_FOREIGN",
        "event" => %{
          "type" => "message",
          "channel" => "C_FOREIGN",
          "user" => "U_CUSTOMER",
          "text" => "From a foreign workspace on the same app",
          "ts" => "1710000207.100000"
        }
      }

      conn = post_signed(conn, payload, "company-secret")

      assert json_response(conn, 200) == %{"ok" => true}
      refute Repo.get_by(Event, external_id: "slack:company:C_FOREIGN:1710000207.100000")
    end

    test "ignores events from a workspace whose installation was disconnected", %{conn: conn} do
      account = insert_account!()

      %Installation{}
      |> Installation.changeset(%{
        app_key: :company,
        team_id: "T_DISCONNECTED",
        team_name: "Disconnected",
        installed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        disconnected_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert!()

      {:ok, _channel} =
        Slack.add_channel(%{
          slack_app: :company,
          channel_id: "C_DISCONNECTED",
          channel_name: "disconnected-customer",
          account_id: account.id
        })

      payload = %{
        "type" => "event_callback",
        "team_id" => "T_DISCONNECTED",
        "event" => %{
          "type" => "message",
          "channel" => "C_DISCONNECTED",
          "user" => "U_CUSTOMER",
          "text" => "Should be ignored after disconnect",
          "ts" => "1710000206.100000"
        }
      }

      conn = post_signed(conn, payload, "company-secret")

      assert json_response(conn, 200) == %{"ok" => true}
      refute Repo.get_by(Event, external_id: "slack:company:C_DISCONNECTED:1710000206.100000")
    end

    test "passes authorized bot users from the Slack event envelope", %{conn: conn} do
      event = %{
        "type" => "message",
        "channel" => "C_SALES",
        "user" => "U_CUSTOMER",
        "text" => "<@U_ATLAS> what's the state of Netflix?",
        "ts" => "1710000201.100000"
      }

      payload = %{
        "type" => "event_callback",
        "event" => event,
        "authorizations" => [
          %{"team_id" => "T123", "user_id" => "U_ATLAS", "is_bot" => true}
        ]
      }

      expected_event =
        event
        |> Map.put("atlas_team_id", "T123")
        |> Map.put("atlas_authorized_user_ids", ["U_ATLAS"])

      expect(RespondToConversation, :start_or_replace, fn ^expected_event, :company, nil -> :ok end)

      conn = post_signed(conn, payload, "company-secret")

      assert json_response(conn, 200) == %{"ok" => true}
    end

    test "rejects a payload that does not match any Slack app signing secret", %{conn: conn} do
      payload = %{
        "type" => "event_callback",
        "event" => %{"type" => "message", "channel" => "C_COMMUNITY", "ts" => "1710000200.100000"}
      }

      conn = post_signed(conn, payload, "wrong-secret")

      assert json_response(conn, 401) == %{"error" => "invalid signature"}
    end
  end

  describe "POST /api/slack/interactions" do
    test "handles a signed GTM opportunity action", %{conn: conn} do
      opportunity =
        insert_gtm_opportunity!()
        |> Opportunity.slack_notification_changeset(%{
          slack_notification_channel_id: "C_MARKETING",
          slack_notification_thread_ts: "1717400000.000100",
          slack_notification_posted_at: ~U[2026-06-01 12:00:00Z]
        })
        |> Repo.update!()

      expect(API, :update_message, fn :company, "C_MARKETING", "1717400000.000100", text, blocks ->
        assert text =~ "Qualified"
        assert is_list(blocks)
        {:ok, %{"ok" => true}}
      end)

      payload = %{
        "type" => "block_actions",
        "container" => %{"channel_id" => "C_MARKETING"},
        "actions" => [
          %{
            "action_id" => "gtm_opportunity:qualify",
            "value" => opportunity.id
          }
        ]
      }

      conn = post_signed_interaction(conn, payload, "company-secret")

      assert json_response(conn, 200) == %{
               "response_type" => "ephemeral",
               "text" => "Marked as qualified."
             }

      assert GTM.get_gtm_opportunity(opportunity.id).status == "qualified"
    end

    test "rejects an interaction payload that does not match any signing secret", %{conn: conn} do
      payload = %{
        "type" => "block_actions",
        "actions" => [%{"action_id" => "gtm_opportunity:review", "value" => Ecto.UUID.generate()}]
      }

      conn = post_signed_interaction(conn, payload, "wrong-secret")

      assert json_response(conn, 401) == %{"error" => "invalid signature"}
    end
  end

  defp post_signed(conn, payload, secret) do
    body = Jason.encode!(payload)
    timestamp = Integer.to_string(System.system_time(:second))
    signature = sign_payload(body, timestamp, secret)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-slack-request-timestamp", timestamp)
    |> put_req_header("x-slack-signature", signature)
    |> post(~p"/api/slack/events", body)
  end

  defp post_signed_interaction(conn, payload, secret) do
    body = URI.encode_query(%{"payload" => Jason.encode!(payload)})
    timestamp = Integer.to_string(System.system_time(:second))
    signature = sign_payload(body, timestamp, secret)

    conn
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("x-slack-request-timestamp", timestamp)
    |> put_req_header("x-slack-signature", signature)
    |> post(~p"/api/slack/interactions", body)
  end

  defp sign_payload(body, timestamp, secret) do
    base = "v0:#{timestamp}:#{body}"

    "v0=" <>
      (:crypto.mac(:hmac, :sha256, secret, base) |> Base.encode16(case: :lower))
  end

  defp insert_account! do
    suffix = System.unique_integer([:positive])

    %Account{}
    |> Account.changeset(%{
      account_key: "test:#{suffix}",
      name: "Account #{suffix}",
      segment: :customer
    })
    |> Repo.insert!()
  end

  defp insert_slack_installation!(team_id) do
    %Installation{}
    |> Installation.changeset(%{
      app_key: :company,
      team_id: team_id,
      team_name: "Company",
      bot_token: "xoxb-company",
      installed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
  end

  defp insert_gtm_opportunity! do
    {:ok, signal} =
      GTM.record_gtm_signal(%{
        company_name: "Acme Platforms",
        company_key: "domain:acme.example",
        domain: "acme.example",
        source: "brave",
        source_ref: "https://acme.example/blog/ios-ci",
        source_url: "https://acme.example/blog/ios-ci",
        title: "Acme scales iOS CI with Tuist and Xcode",
        excerpt: "iOS Swift Xcode monorepo platform mobile CI modules slow cache flaky reliability.",
        matched_terms: ["iOS", "Swift", "Xcode", "Tuist", "monorepo", "platform", "mobile", "CI", "slow", "cache"],
        signal_kind: "engineering_blog",
        confidence: 95,
        observed_at: ~U[2026-06-01 12:00:00Z],
        metadata: %{}
      })

    GTM.get_gtm_opportunity(signal.opportunity_id)
  end
end
