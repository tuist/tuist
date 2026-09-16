defmodule Atlas.Slack.EventsTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Slack
  alias Atlas.Slack.API
  alias Atlas.Slack.Bot
  alias Atlas.Slack.Events, as: SlackEvents
  alias Atlas.Slack.Message, as: SlackMessage
  alias Atlas.Slack.User, as: SlackUser
  alias Atlas.Slack.Workers.RespondToConversation

  setup :verify_on_exit!

  @user_profiles %{
    "U123" => %{
      slack_user_id: "U123",
      name: "alice",
      real_name: "Alice Internal",
      display_name: "alice",
      avatar_url: "https://example.com/avatars/alice.png",
      is_bot: false,
      is_external: false
    },
    "U456" => %{
      slack_user_id: "U456",
      name: "bob",
      real_name: "Bob Customer",
      display_name: "bob",
      avatar_url: "https://example.com/avatars/bob.png",
      is_bot: false,
      is_external: true
    }
  }

  setup do
    stub(API, :get_user_info, fn _app_key, user_id ->
      case Map.fetch(@user_profiles, user_id) do
        {:ok, profile} -> {:ok, profile}
        :error -> {:error, {:unknown_user, user_id}}
      end
    end)

    # `1999` prefix marks timestamps that should simulate a Slack permalink fetch
    # failure. Still a valid unix timestamp so `parse_slack_timestamp/1` succeeds.
    stub(API, :get_permalink, fn _app_key, channel_id, ts ->
      if String.starts_with?(ts, "1999") do
        {:error, :rate_limited}
      else
        clean_ts = String.replace(ts, ".", "")
        {:ok, "https://acme.slack.com/archives/#{channel_id}/p#{clean_ts}"}
      end
    end)

    {:ok, channel} =
      Slack.add_channel(%{channel_id: "C123", channel_name: "builds"})

    {:ok, channel: channel}
  end

  describe "handle_event/1 (channel without account link)" do
    test "ignores messages on monitored channels that have no account link" do
      payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U123",
        "text" => "Build is failing on main",
        "ts" => "1710000000.100000"
      }

      assert :ignored = SlackEvents.handle_event(payload, :company)
    end

    test "responds to regular message events that mention the authorized bot user", %{channel: channel} do
      payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U123",
        "text" => "<@U_ATLAS> what's the state of Netflix?",
        "ts" => "1710000001.100000",
        "atlas_authorized_user_ids" => ["U_ATLAS"]
      }

      expect(RespondToConversation, :start_or_replace, fn ^payload, :company, ^channel -> :ok end)

      assert :ok = SlackEvents.handle_event(payload, :company)
      assert Slack.get_message_by_ts(channel, "1710000001.100000") == nil
    end

    test "ignores regular message mentions for other users" do
      payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U123",
        "text" => "<@U_OTHER> what's the state of Netflix?",
        "ts" => "1710000002.100000",
        "atlas_authorized_user_ids" => ["U_ATLAS"]
      }

      reject(&RespondToConversation.start_or_replace/3)

      assert :ignored = SlackEvents.handle_event(payload, :company)
    end

    test "responds to authorized bot mentions from untracked channels" do
      payload = %{
        "type" => "message",
        "channel" => "C_UNKNOWN",
        "user" => "U123",
        "text" => "<@U_ATLAS> what's the state of Netflix?",
        "ts" => "1710000003.100000",
        "atlas_authorized_user_ids" => ["U_ATLAS"]
      }

      expect(RespondToConversation, :start_or_replace, fn ^payload, :company, nil -> :ok end)

      assert :ok = SlackEvents.handle_event(payload, :company)
    end

    test "responds to app mentions from untracked channels" do
      payload = %{
        "type" => "app_mention",
        "channel" => "C_UNKNOWN",
        "user" => "U123",
        "text" => "<@U_ATLAS> capture this as a social idea",
        "ts" => "1710000004.100000"
      }

      expect(RespondToConversation, :start_or_replace, fn ^payload, :company, nil -> :ok end)

      assert :ok = SlackEvents.handle_event(payload, :company)
    end

    test "responds to thread replies after Atlas was mentioned earlier in the same thread", %{channel: channel} do
      payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U123",
        "thread_ts" => "1710000001.100000",
        "ts" => "1710000003.100000",
        "text" => "The company is Toss and the domain is toss.im",
        "atlas_authorized_user_ids" => ["U_ATLAS"]
      }

      thread_messages = [
        %{
          user_id: "U123",
          text: "<@U_ATLAS> can you create an account for this one?",
          ts: "1710000001.100000",
          thread_ts: "1710000001.100000"
        },
        %{
          bot_id: "B_ATLAS",
          username: "Atlas",
          text: "I'd be happy to help.",
          ts: "1710000002.100000",
          thread_ts: "1710000001.100000"
        }
      ]

      stub(API, :list_thread_messages, fn :company, "C123", "1710000001.100000" ->
        {:ok, thread_messages}
      end)

      expect(RespondToConversation, :start_or_replace, fn event, :company, ^channel ->
        assert event["atlas_thread_messages"] == thread_messages
        assert event["ts"] == payload["ts"]
        :ok
      end)

      assert :ok = SlackEvents.handle_event(payload, :company)
    end

    test "ignores thread replies when Atlas has not been looped into the thread yet" do
      payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U123",
        "thread_ts" => "1710000001.100000",
        "ts" => "1710000004.100000",
        "text" => "The company is Toss and the domain is toss.im",
        "atlas_authorized_user_ids" => ["U_ATLAS"]
      }

      stub(API, :list_thread_messages, fn :company, "C123", "1710000001.100000" ->
        {:ok,
         [
           %{
             user_id: "U123",
             text: "Can someone help with this account?",
             ts: "1710000001.100000",
             thread_ts: "1710000001.100000"
           }
         ]}
      end)

      reject(&RespondToConversation.start_or_replace/3)

      assert :ignored = SlackEvents.handle_event(payload, :company)
    end

    test "responds to thread replies after an earlier Atlas bot reply from a configured app", %{channel: channel} do
      payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U123",
        "thread_ts" => "1710000001.100000",
        "ts" => "1710000005.100000",
        "text" => "Can you confirm the account name too?",
        "atlas_authorized_user_ids" => ["U_ATLAS"]
      }

      stub(Bot, :apps, fn ->
        [
          %{name: "Tuist Atlas Company"}
        ]
      end)

      thread_messages = [
        %{
          user_id: "U123",
          text: "Can someone help with this account?",
          ts: "1710000001.100000",
          thread_ts: "1710000001.100000"
        },
        %{
          bot_id: "B_ATLAS",
          username: "Tuist Atlas Company",
          subtype: "bot_message",
          text: "Checking Atlas context",
          ts: "1710000002.100000",
          thread_ts: "1710000001.100000"
        }
      ]

      stub(API, :list_thread_messages, fn :company, "C123", "1710000001.100000" ->
        {:ok, thread_messages}
      end)

      expect(RespondToConversation, :start_or_replace, fn event, :company, ^channel ->
        assert event["atlas_thread_messages"] == thread_messages
        assert event["ts"] == payload["ts"]
        :ok
      end)

      assert :ok = SlackEvents.handle_event(payload, :company)
    end

    test "responds to thread replies on Atlas-authored outcome review messages without a mention", %{channel: channel} do
      payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U123",
        "thread_ts" => "1710000100.100000",
        "ts" => "1710000101.100000",
        "text" => "We've been chatting with them quite actively. How is the outcome looking?",
        "atlas_authorized_user_ids" => ["U_ATLAS"]
      }

      thread_messages = [
        %{
          user_id: "U_ATLAS",
          bot_id: "B_ATLAS",
          username: "Tuist Atlas",
          subtype: "bot_message",
          text:
            "Outcome review: Qonto - Dedicated Slack channel and cache infrastructure\nAccount ID: account-123\nOutcome ID: outcome-123",
          ts: "1710000100.100000",
          thread_ts: "1710000100.100000"
        }
      ]

      stub(API, :list_thread_messages, fn :company, "C123", "1710000100.100000" ->
        {:ok, thread_messages}
      end)

      expect(RespondToConversation, :start_or_replace, fn event, :company, ^channel ->
        assert event["atlas_thread_messages"] == thread_messages
        assert event["ts"] == payload["ts"]
        :ok
      end)

      assert :ok = SlackEvents.handle_event(payload, :company)
    end
  end

  describe "handle_event/1 (account-linked channel)" do
    setup %{channel: channel} do
      account =
        %Account{}
        |> Account.changeset(%{
          account_key: "enterprise:acme",
          name: "Acme",
          segment: :customer
        })
        |> Repo.insert!()

      {:ok, channel} = Slack.update_channel_account(channel, account.id)

      %{account: account, channel: channel}
    end

    test "stores a top-level message as a Slack message and an account event", %{
      account: account
    } do
      payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U456",
        "text" => "Could you confirm the renewal terms?",
        "ts" => "1710000000.100000"
      }

      assert {:ok, %SlackMessage{} = message} = SlackEvents.handle_event(payload, :company)

      assert message.text == "Could you confirm the renewal terms?"
      assert message.slack_ts == "1710000000.100000"
      assert message.permalink == "https://acme.slack.com/archives/C123/p1710000000100000"
      assert message.account_event_id

      slack_user = Repo.get!(SlackUser, message.slack_user_id)
      assert slack_user.slack_user_id == "U456"
      assert slack_user.slack_app == :company
      assert slack_user.is_external
      assert slack_user.avatar_url == "https://example.com/avatars/bob.png"

      event = Repo.get!(Event, message.account_event_id)
      assert event.account_id == account.id
      assert event.kind == "slack_message"
      assert event.source == "slack"
      assert event.url == "https://acme.slack.com/archives/C123/p1710000000100000"
      assert event.title == "Could you confirm the renewal terms?"
      assert event.body == "Could you confirm the renewal terms?"
      assert event.metadata["channel_name"] == "builds"
      assert event.metadata["channel_id"] == "C123"
      assert event.metadata["slack_app"] == "company"
      assert event.metadata["author_name"] == "bob"
      assert event.metadata["author_avatar_url"] == "https://example.com/avatars/bob.png"
      assert event.metadata["author_is_external"] == true
    end

    test "uses the Slack app key when resolving channels", %{account: account} do
      {:ok, community_channel} =
        Slack.add_channel(%{
          slack_app: :community,
          channel_id: "C123",
          channel_name: "community-builds",
          account_id: account.id
        })

      payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U456",
        "text" => "Community workspace message",
        "ts" => "1710000100.100000"
      }

      assert {:ok, %SlackMessage{} = message} = SlackEvents.handle_event(payload, :community)
      assert message.slack_channel_id == community_channel.id

      event = Repo.get!(Event, message.account_event_id)
      assert event.external_id == "slack:community:C123:1710000100.100000"
      assert event.metadata["slack_app"] == "community"
      assert event.metadata["channel_name"] == "community-builds"
    end

    test "stores a thread reply against the same channel without creating a new event", %{
      account: account,
      channel: channel
    } do
      parent_payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U123",
        "text" => "Renewal terms drafted; sending shortly.",
        "ts" => "1710000000.100000"
      }

      assert {:ok, _parent} = SlackEvents.handle_event(parent_payload, :company)

      reply_payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U456",
        "thread_ts" => "1710000000.100000",
        "ts" => "1710000300.200000",
        "text" => "Got it, thanks."
      }

      assert {:ok, %SlackMessage{} = reply} = SlackEvents.handle_event(reply_payload, :company)
      assert reply.thread_ts == "1710000000.100000"
      assert reply.account_event_id == nil
      assert reply.slack_ts == "1710000300.200000"

      events =
        Event
        |> where([e], e.account_id == ^account.id)
        |> Repo.all()

      assert length(events) == 1

      replies = Slack.list_thread_replies(channel, "1710000000.100000")
      assert [%SlackMessage{slack_ts: "1710000300.200000"}] = replies
    end

    test "captures the message even when the permalink fetch fails", %{account: account} do
      payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U123",
        "text" => "Permalink will fail",
        "ts" => "1999000000.000001"
      }

      assert {:ok, %SlackMessage{} = message} = SlackEvents.handle_event(payload, :company)
      assert message.permalink == nil

      event = Repo.get!(Event, message.account_event_id)
      assert event.account_id == account.id
      assert event.url == nil
    end

    test "captures the message with no author when the user lookup fails", %{account: account} do
      payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U_UNKNOWN",
        "text" => "Author resolution will fail",
        "ts" => "1710000000.500000"
      }

      assert {:ok, %SlackMessage{} = message} = SlackEvents.handle_event(payload, :company)
      assert message.slack_user_id == nil

      event = Repo.get!(Event, message.account_event_id)
      assert event.account_id == account.id
      assert event.metadata["author_name"] == nil
      assert event.metadata["author_avatar_url"] == nil
      assert event.metadata["author_is_external"] == nil
      assert event.metadata["author_slack_user_id"] == nil
    end

    test "captures app mentions and starts a threaded conversation responder", %{
      account: account,
      channel: channel
    } do
      payload = %{
        "type" => "app_mention",
        "channel" => "C123",
        "user" => "U456",
        "text" => "<@U_ATLAS> What is the renewal status?",
        "ts" => "1710000600.100000"
      }

      expect(RespondToConversation, :start_or_replace, fn ^payload, :company, ^channel -> :ok end)

      assert :ok = SlackEvents.handle_event(payload, :company)

      message = Slack.get_message_by_ts(channel, "1710000600.100000")
      assert message.text == "<@U_ATLAS> What is the renewal status?"
      assert message.account_event_id

      event = Repo.get!(Event, message.account_event_id)
      assert event.account_id == account.id
      assert event.external_id == "slack:company:C123:1710000600.100000"
    end

    test "rolls back the slack_message insert when the account_event insert fails",
         %{account: account, channel: channel} do
      conflicting_ts = "1710000000.999999"

      %Event{}
      |> Event.changeset(%{
        external_id: "slack:company:C123:#{conflicting_ts}",
        source: "slack",
        kind: "slack_message",
        title: "preexisting",
        occurred_at: ~U[2026-04-29 00:00:00Z],
        account_id: account.id
      })
      |> Repo.insert!()

      payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U123",
        "text" => "Will collide on external_id",
        "ts" => conflicting_ts
      }

      assert {:error, _changeset} = SlackEvents.handle_event(payload, :company)

      assert Slack.get_message_by_ts(channel, conflicting_ts) == nil
    end
  end

  describe "verify_signature/4" do
    @signing_secret "shhhhh"

    defp sign(body, timestamp, secret \\ @signing_secret) do
      base = "v0:#{timestamp}:#{body}"

      "v0=" <>
        (:crypto.mac(:hmac, :sha256, secret, base) |> Base.encode16(case: :lower))
    end

    test "accepts a correctly signed payload" do
      body = ~s({"hello":"world"})
      timestamp = "1714000000"
      sig = sign(body, timestamp)

      assert :ok = SlackEvents.verify_signature(body, timestamp, sig, @signing_secret)
    end

    test "rejects a payload signed with a different secret" do
      body = "{}"
      timestamp = "1714000000"
      bad_sig = sign(body, timestamp, "other-secret")

      assert {:error, :invalid_signature} =
               SlackEvents.verify_signature(body, timestamp, bad_sig, @signing_secret)
    end

    test "rejects a payload whose body has been tampered with" do
      body = "{}"
      timestamp = "1714000000"
      sig = sign(body, timestamp)

      assert {:error, :invalid_signature} =
               SlackEvents.verify_signature("{\"tampered\":true}", timestamp, sig, @signing_secret)
    end

    test "rejects a payload whose timestamp has been tampered with" do
      body = "{}"
      sig = sign(body, "1714000000")

      assert {:error, :invalid_signature} =
               SlackEvents.verify_signature(body, "1714000999", sig, @signing_secret)
    end
  end

  describe "handle_event/1 (other event shapes)" do
    test "ignores message events that carry a subtype" do
      payload = %{
        "type" => "message",
        "subtype" => "channel_join",
        "channel" => "C123",
        "user" => "U123",
        "ts" => "1710000000.100000"
      }

      assert :ignored = SlackEvents.handle_event(payload, :company)
    end

    test "ignores bot-authored message events even when Slack omits the subtype" do
      payload = %{
        "type" => "message",
        "channel" => "C123",
        "user" => "U_ATLAS",
        "text" => "Got it, Pedro! Stopping now.",
        "ts" => "1710000000.200000",
        "atlas_authorized_user_ids" => ["U_ATLAS"]
      }

      reject(&RespondToConversation.start_or_replace/3)

      assert :ignored = SlackEvents.handle_event(payload, :company)
    end

    test "ignores assistant message events that carry bot metadata but no subtype" do
      payload = %{
        "type" => "message",
        "channel" => "C123",
        "bot_id" => "B_ATLAS",
        "app_id" => "A_ATLAS",
        "text" => "Reading recent activity",
        "ts" => "1710000000.300000",
        "atlas_authorized_user_ids" => ["U_ATLAS"]
      }

      reject(&RespondToConversation.start_or_replace/3)

      assert :ignored = SlackEvents.handle_event(payload, :company)
    end

    test "ignores messages from unmonitored channels" do
      payload = %{
        "type" => "message",
        "channel" => "C_UNKNOWN",
        "user" => "U123",
        "text" => "no channel",
        "ts" => "1710000000.100000"
      }

      assert :ignored = SlackEvents.handle_event(payload, :company)
    end

    test "ignores non-message events" do
      assert :ignored = SlackEvents.handle_event(%{"type" => "reaction_added"}, :company)
    end
  end

  describe "handle_event/1 (link_shared)" do
    setup do
      account =
        %Account{}
        |> Account.changeset(%{
          account_key: "enterprise:contoso",
          name: "Contoso",
          segment: :customer,
          status: "active",
          deal_stage: "negotiation",
          description: "Long-time strategic partner.",
          primary_domain: "contoso.com",
          currency: "USD",
          current_value: Decimal.new("120000"),
          next_renewal_date: ~D[2026-09-15],
          contacts_count: 8,
          latest_activity_at: ~U[2026-04-30 12:00:00Z]
        })
        |> Repo.insert!()

      %{account: account}
    end

    test "renders a rich Block Kit unfurl for the company app", %{account: account} do
      url = "https://localhost/accounts/#{account.id}"

      expect(API, :unfurl_link, fn :company, channel, ts, unfurls ->
        assert channel == "C_LINKS"
        assert ts == "1710000500.000100"
        assert Map.keys(unfurls) == [url]
        blocks = unfurls[url]["blocks"]
        [title, highlights, context] = blocks

        assert title["type"] == "section"

        assert title["text"] == %{
                 "type" => "mrkdwn",
                 "text" => "*<#{url}|Contoso>*\nLong-time strategic partner."
               }

        assert title["accessory"] == %{
                 "type" => "image",
                 "image_url" => "https://www.google.com/s2/favicons?domain=contoso.com&sz=128",
                 "alt_text" => "Contoso"
               }

        assert highlights == %{
                 "type" => "section",
                 "fields" => [
                   %{"type" => "mrkdwn", "text" => "*Current Value*\nUSD 120,000.00"},
                   %{"type" => "mrkdwn", "text" => "*Next Renewal*\nSep 15, 2026"}
                 ]
               }

        assert context["type"] == "context"
        [icon, summary] = context["elements"]
        assert icon["type"] == "image"
        assert icon["image_url"] =~ ~r{^https?://[^/]+/apple-touch-icon\.png$}
        assert icon["alt_text"] == "Atlas"

        assert summary == %{
                 "type" => "mrkdwn",
                 "text" => "*Atlas* · Customer · Negotiation · Active · 8 contacts · Last activity Apr 30, 2026"
               }

        :ok
      end)

      payload = %{
        "type" => "link_shared",
        "channel" => "C_LINKS",
        "message_ts" => "1710000500.000100",
        "links" => [%{"domain" => "localhost", "url" => url}]
      }

      assert :ok = SlackEvents.handle_event(payload, :company)
    end

    test "renders a minimal unfurl for an account with no metadata or domain" do
      account =
        %Account{}
        |> Account.changeset(%{
          account_key: "lead:initech",
          name: "Initech",
          segment: :lead
        })
        |> Repo.insert!()

      url = "https://localhost/accounts/#{account.id}"

      expect(API, :unfurl_link, fn :company, _channel, _ts, unfurls ->
        [title, context] = unfurls[url]["blocks"]
        assert title["text"]["text"] == "*<#{url}|Initech>*"
        refute Map.has_key?(title, "accessory")

        assert context["elements"] |> List.last() == %{
                 "type" => "mrkdwn",
                 "text" => "*Atlas* · Lead"
               }

        :ok
      end)

      payload = %{
        "type" => "link_shared",
        "channel" => "C_LINKS",
        "message_ts" => "1710000500.000100",
        "links" => [%{"domain" => "localhost", "url" => url}]
      }

      assert :ok = SlackEvents.handle_event(payload, :company)
    end

    test "escapes mrkdwn-special characters in the account name and description" do
      account =
        %Account{}
        |> Account.changeset(%{
          account_key: "customer:angle",
          name: "A&B <Holdings>",
          segment: :customer,
          description: "Owns <example.com> & runs payments."
        })
        |> Repo.insert!()

      url = "https://localhost/accounts/#{account.id}"

      expect(API, :unfurl_link, fn :company, _channel, _ts, unfurls ->
        [title | _rest] = unfurls[url]["blocks"]

        assert title["text"]["text"] ==
                 "*<#{url}|A&amp;B &lt;Holdings&gt;>*\nOwns &lt;example.com&gt; &amp; runs payments."

        :ok
      end)

      payload = %{
        "type" => "link_shared",
        "channel" => "C_LINKS",
        "message_ts" => "1710000500.000100",
        "links" => [%{"domain" => "localhost", "url" => url}]
      }

      assert :ok = SlackEvents.handle_event(payload, :company)
    end

    test "ignores link_shared events from the community app", %{account: account} do
      url = "https://localhost/accounts/#{account.id}"

      reject(&API.unfurl_link/4)

      payload = %{
        "type" => "link_shared",
        "channel" => "C_LINKS",
        "message_ts" => "1710000500.000100",
        "links" => [%{"domain" => "localhost", "url" => url}]
      }

      assert :ignored = SlackEvents.handle_event(payload, :community)
    end

    test "ignores URLs hosted on a different domain", %{account: account} do
      reject(&API.unfurl_link/4)

      payload = %{
        "type" => "link_shared",
        "channel" => "C_LINKS",
        "message_ts" => "1710000500.000100",
        "links" => [
          %{"domain" => "example.com", "url" => "https://example.com/accounts/#{account.id}"}
        ]
      }

      assert :ignored = SlackEvents.handle_event(payload, :company)
    end

    test "ignores URLs whose path does not match an account route" do
      reject(&API.unfurl_link/4)

      payload = %{
        "type" => "link_shared",
        "channel" => "C_LINKS",
        "message_ts" => "1710000500.000100",
        "links" => [%{"domain" => "localhost", "url" => "https://localhost/sessions"}]
      }

      assert :ignored = SlackEvents.handle_event(payload, :company)
    end

    test "ignores URLs that point to a non-existent account" do
      reject(&API.unfurl_link/4)

      missing_id = "01900000-0000-7000-8000-000000000000"

      payload = %{
        "type" => "link_shared",
        "channel" => "C_LINKS",
        "message_ts" => "1710000500.000100",
        "links" => [%{"domain" => "localhost", "url" => "https://localhost/accounts/#{missing_id}"}]
      }

      assert :ignored = SlackEvents.handle_event(payload, :company)
    end

    test "ignores URLs whose account id is not a valid UUID" do
      reject(&API.unfurl_link/4)

      payload = %{
        "type" => "link_shared",
        "channel" => "C_LINKS",
        "message_ts" => "1710000500.000100",
        "links" => [%{"domain" => "localhost", "url" => "https://localhost/accounts/not-a-uuid"}]
      }

      assert :ignored = SlackEvents.handle_event(payload, :company)
    end
  end

  describe "handle_event/1 (reaction_added on memory proposal)" do
    test "confirms the pending memory when a teammate reacts with :white_check_mark:", %{channel: channel} do
      {:ok, node} =
        Atlas.Memory.create_node(%{
          kind: :fact,
          body: "Proposed memory.",
          confirmation: :pending,
          slack_channel_id: channel.id,
          proposal_slack_ts: "1710000300.000100"
        })

      payload = %{
        "type" => "reaction_added",
        "user" => "U123",
        "reaction" => "white_check_mark",
        "item" => %{
          "type" => "message",
          "channel" => "C123",
          "ts" => "1710000300.000100"
        }
      }

      assert :ok = SlackEvents.handle_event(payload, :company)

      assert %Atlas.Memory.Node{confirmation: :confirmed} = Atlas.Memory.get_node(node.id)
    end

    test "discards the pending memory when a teammate reacts with :x:", %{channel: channel} do
      {:ok, node} =
        Atlas.Memory.create_node(%{
          kind: :fact,
          body: "Proposed memory.",
          confirmation: :pending,
          slack_channel_id: channel.id,
          proposal_slack_ts: "1710000300.000100"
        })

      payload = %{
        "type" => "reaction_added",
        "user" => "U123",
        "reaction" => "x",
        "item" => %{
          "type" => "message",
          "channel" => "C123",
          "ts" => "1710000300.000100"
        }
      }

      assert :ok = SlackEvents.handle_event(payload, :company)

      assert %Atlas.Memory.Node{forgotten: true, confirmation: :pending} =
               Atlas.Memory.get_node(node.id)
    end

    test "ignores reactions from the bot itself" do
      {:ok, node} =
        Atlas.Memory.create_node(%{
          kind: :fact,
          body: "Proposed memory.",
          confirmation: :pending,
          slack_channel_id: Slack.find_channel(:company, "C123").id,
          proposal_slack_ts: "1710000300.000100"
        })

      payload = %{
        "type" => "reaction_added",
        "user" => "UBOT",
        "reaction" => "white_check_mark",
        "item" => %{
          "type" => "message",
          "channel" => "C123",
          "ts" => "1710000300.000100"
        },
        "atlas_authorized_user_ids" => ["UBOT"]
      }

      assert :ignored = SlackEvents.handle_event(payload, :company)
      assert %Atlas.Memory.Node{confirmation: :pending} = Atlas.Memory.get_node(node.id)
    end

    test "ignores reactions that do not target a known pending proposal" do
      payload = %{
        "type" => "reaction_added",
        "user" => "U123",
        "reaction" => "white_check_mark",
        "item" => %{
          "type" => "message",
          "channel" => "C123",
          "ts" => "1710000999.000100"
        }
      }

      assert :ignored = SlackEvents.handle_event(payload, :company)
    end

    test "ignores reactions other than :white_check_mark: and :x:", %{channel: channel} do
      {:ok, node} =
        Atlas.Memory.create_node(%{
          kind: :fact,
          body: "Proposed memory.",
          confirmation: :pending,
          slack_channel_id: channel.id,
          proposal_slack_ts: "1710000300.000100"
        })

      payload = %{
        "type" => "reaction_added",
        "user" => "U123",
        "reaction" => "thumbsup",
        "item" => %{
          "type" => "message",
          "channel" => "C123",
          "ts" => "1710000300.000100"
        }
      }

      assert :ignored = SlackEvents.handle_event(payload, :company)
      assert %Atlas.Memory.Node{confirmation: :pending} = Atlas.Memory.get_node(node.id)
    end
  end
end
