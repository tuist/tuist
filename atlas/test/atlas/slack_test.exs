defmodule Atlas.SlackTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Audit.Activity
  alias Atlas.Slack
  alias Atlas.Slack.API
  alias Atlas.Slack.Channel
  alias Atlas.Slack.Message
  alias Atlas.Slack.User

  setup :verify_on_exit!

  describe "channels and accounts" do
    setup do
      %{account: insert_account!()}
    end

    test "add_channel/1 ignores user-supplied account_id keys when none is requested", %{
      account: account
    } do
      # Even if a malicious caller stuffs an account_id in attrs, it must be
      # taken via the dedicated path; the schema cast does not include FKs.
      {:ok, channel} =
        Slack.add_channel(%{
          channel_id: "C1",
          channel_name: "support",
          account_id: account.id
        })

      assert channel.account_id == account.id

      activity = Repo.get_by!(Activity, action: "slack_channel.tracked", target_id: channel.id)
      assert activity.metadata["path"] == "/commercial/sales/accounts/#{account.id}"
    end

    test "update_channel_account/2 links a channel to an account", %{account: account} do
      {:ok, channel} =
        Slack.add_channel(%{channel_id: "C1", channel_name: "support"})

      assert {:ok, updated} = Slack.update_channel_account(channel, account.id)
      assert updated.account_id == account.id
    end

    test "update_channel_account/2 unlinks a channel from an account", %{account: account} do
      {:ok, channel} =
        Slack.add_channel(%{
          channel_id: "C1",
          channel_name: "support",
          account_id: account.id
        })

      assert {:ok, updated} = Slack.update_channel_account(channel, nil)
      assert updated.account_id == nil

      {:ok, blanked} = Slack.update_channel_account(updated, "")
      assert blanked.account_id == nil
    end

    test "list_channels_for_account/1 returns channels linked to the account, sorted",
         %{account: account} do
      {:ok, _} =
        Slack.add_channel(%{
          channel_id: "C2",
          channel_name: "zebra",
          account_id: account.id
        })

      {:ok, _} =
        Slack.add_channel(%{
          channel_id: "C3",
          channel_name: "alpha",
          account_id: account.id
        })

      # An unrelated channel that should not appear.
      {:ok, _} =
        Slack.add_channel(%{channel_id: "C4", channel_name: "noise"})

      channels = Slack.list_channels_for_account(account)
      assert [%Channel{channel_name: "alpha"}, %Channel{channel_name: "zebra"}] = channels
      assert Enum.all?(channels, &(&1.account_id == account.id))
    end

    test "allows legacy records to keep their Slack workspace key" do
      assert {:ok, %Channel{slack_app: :company}} =
               Slack.add_channel(%{
                 slack_app: :company,
                 channel_id: "CSHARED",
                 channel_name: "company-support"
               })

      assert {:ok, %Channel{slack_app: :community}} =
               Slack.add_channel(%{
                 slack_app: :community,
                 channel_id: "CSHARED",
                 channel_name: "community-support"
               })
    end

    test "does not cast slack_app through the channel changeset" do
      changeset =
        Channel.changeset(%Channel{slack_app: :company}, %{
          slack_app: :community,
          channel_id: "C1",
          channel_name: "support"
        })

      assert Ecto.Changeset.get_field(changeset, :slack_app) == :company
    end
  end

  describe "users" do
    test "upsert_user/1 inserts a new row when none exists" do
      assert {:ok, %User{} = user} =
               Slack.upsert_user(:company, %{
                 slack_user_id: "U1",
                 name: "alice",
                 avatar_url: "https://x/a.png",
                 is_external: false
               })

      assert user.slack_user_id == "U1"
      assert user.slack_app == :company
      assert user.avatar_url == "https://x/a.png"
      assert user.last_synced_at != nil
    end

    test "does not cast slack_app through the user changeset" do
      changeset =
        User.changeset(%User{slack_app: :company}, %{
          slack_app: :community,
          slack_user_id: "U1"
        })

      assert Ecto.Changeset.get_field(changeset, :slack_app) == :company
    end

    test "upsert_user/1 updates an existing row in place" do
      {:ok, original} =
        Slack.upsert_user(:company, %{
          slack_user_id: "U1",
          name: "alice",
          avatar_url: "https://x/a.png"
        })

      {:ok, updated} =
        Slack.upsert_user(:company, %{
          slack_user_id: "U1",
          name: "alice",
          avatar_url: "https://x/new.png",
          is_external: true
        })

      assert updated.id == original.id
      assert updated.avatar_url == "https://x/new.png"
      assert updated.is_external == true
    end

    test "get_user/1 returns nil when not present" do
      assert Slack.get_user(:company, "Umissing") == nil
    end

    test "get_user/1 returns the cached row when present" do
      {:ok, _} = Slack.upsert_user(:company, %{slack_user_id: "U1"})
      assert %User{slack_user_id: "U1"} = Slack.get_user(:company, "U1")
    end

    test "upsert_user/2 scopes cached users by Slack app" do
      {:ok, company_user} = Slack.upsert_user(:company, %{slack_user_id: "U1", name: "company"})
      {:ok, community_user} = Slack.upsert_user(:community, %{slack_user_id: "U1", name: "community"})

      assert company_user.id != community_user.id
      assert Slack.get_user(:company, "U1").name == "company"
      assert Slack.get_user(:community, "U1").name == "community"
    end
  end

  describe "messages and threads" do
    setup do
      account = insert_account!()

      {:ok, channel} =
        Slack.add_channel(%{
          channel_id: "C1",
          channel_name: "support",
          account_id: account.id
        })

      {:ok, alice} = Slack.upsert_user(:company, %{slack_user_id: "U_ALICE", name: "alice"})
      {:ok, bob} = Slack.upsert_user(:company, %{slack_user_id: "U_BOB", name: "bob"})

      %{account: account, channel: channel, alice: alice, bob: bob}
    end

    test "list_thread_replies/2 returns only the thread's replies, oldest first", %{
      account: account,
      channel: channel,
      alice: alice,
      bob: bob
    } do
      {:ok, parent_event} = insert_slack_event(account, "1.0")

      {:ok, _parent} =
        Slack.insert_message(channel, alice, parent_event, %{
          slack_ts: "1.0",
          thread_ts: nil,
          posted_at: ~U[2026-04-01 10:00:00Z]
        })

      {:ok, _reply_b} =
        Slack.insert_message(channel, bob, nil, %{
          slack_ts: "3.0",
          thread_ts: "1.0",
          posted_at: ~U[2026-04-01 10:30:00Z]
        })

      {:ok, _reply_a} =
        Slack.insert_message(channel, alice, nil, %{
          slack_ts: "2.0",
          thread_ts: "1.0",
          posted_at: ~U[2026-04-01 10:15:00Z]
        })

      # Different thread — should not appear in the result.
      {:ok, _other} =
        Slack.insert_message(channel, bob, nil, %{
          slack_ts: "9.0",
          thread_ts: "8.0",
          posted_at: ~U[2026-04-01 11:00:00Z]
        })

      replies = Slack.list_thread_replies(channel, "1.0")

      assert length(replies) == 2
      assert Enum.map(replies, & &1.slack_ts) == ["2.0", "3.0"]
      assert Enum.map(replies, & &1.slack_user.slack_user_id) == ["U_ALICE", "U_BOB"]
    end

    test "thread_replies_by_account_event/1 returns an empty map for empty input" do
      assert Slack.thread_replies_by_account_event([]) == %{}
    end

    test "thread_replies_by_account_event/1 returns an empty map when no parents match" do
      assert Slack.thread_replies_by_account_event([Ecto.UUID.generate()]) == %{}
    end

    test "thread_replies_by_account_event/1 groups replies by their parent event id", %{
      account: account,
      channel: channel,
      alice: alice,
      bob: bob
    } do
      {:ok, event_a} = insert_slack_event(account, "100.0")
      {:ok, event_b} = insert_slack_event(account, "200.0")

      {:ok, _parent_a} =
        Slack.insert_message(channel, alice, event_a, %{
          slack_ts: "100.0",
          thread_ts: nil,
          posted_at: ~U[2026-04-01 10:00:00Z]
        })

      {:ok, _parent_b} =
        Slack.insert_message(channel, bob, event_b, %{
          slack_ts: "200.0",
          thread_ts: nil,
          posted_at: ~U[2026-04-02 10:00:00Z]
        })

      {:ok, _reply_a1} =
        Slack.insert_message(channel, bob, nil, %{
          slack_ts: "101.0",
          thread_ts: "100.0",
          posted_at: ~U[2026-04-01 10:15:00Z]
        })

      {:ok, _reply_b1} =
        Slack.insert_message(channel, alice, nil, %{
          slack_ts: "201.0",
          thread_ts: "200.0",
          posted_at: ~U[2026-04-02 10:15:00Z]
        })

      grouped = Slack.thread_replies_by_account_event([event_a.id, event_b.id])

      assert Map.keys(grouped) |> Enum.sort() == Enum.sort([event_a.id, event_b.id])

      assert [%Message{slack_ts: "101.0", slack_user: %User{slack_user_id: "U_BOB"}}] =
               grouped[event_a.id]

      assert [%Message{slack_ts: "201.0", slack_user: %User{slack_user_id: "U_ALICE"}}] =
               grouped[event_b.id]
    end
  end

  describe "list_available_channels/0" do
    test "uses the Slack API response when it succeeds" do
      API
      |> stub(:list_channels, fn :company ->
        {:ok,
         [
           %{
             slack_app: :company,
             slack_channel_id: "C_API_1",
             name: "support",
             is_shared: false,
             is_ext_shared: false,
             is_member: true,
             is_private: false
           }
         ]}
      end)

      options = Slack.list_available_channels()
      assert length(options) == 1

      [support] = options

      assert support.name == "support"
      assert support.slack_app == :company
      assert support.is_ext_shared == false
    end

    test "falls back to channels tracked in the DB when the API errors" do
      API
      |> stub(:list_channels, fn _app_key -> {:error, :stubbed} end)

      {:ok, _} = Slack.add_channel(%{channel_id: "C_DB_1", channel_name: "support"})

      options = Slack.list_available_channels()
      assert Enum.map(options, & &1.name) == ["support"]
      assert Enum.all?(options, &(&1.is_ext_shared == false))
    end

    test "returns an empty list when the API errors and no channels are tracked" do
      API
      |> stub(:list_channels, fn _app_key -> {:error, :stubbed} end)

      assert Slack.list_available_channels() == []
    end
  end

  describe "set_account_channel/3" do
    setup do
      stub(API, :list_channels, fn _app_key -> {:error, :stubbed} end)
      account = insert_account!()

      {:ok, channel_a} =
        Slack.add_channel(%{channel_id: "C_A", channel_name: "alpha"})

      options = [
        %{
          slack_app: :company,
          slack_channel_id: "C_A",
          name: "alpha",
          is_shared: false,
          is_ext_shared: false
        },
        %{
          slack_app: :community,
          slack_channel_id: "C_NEW",
          name: "new-channel",
          is_shared: false,
          is_ext_shared: false
        }
      ]

      %{account: account, channel_a: channel_a, options: options}
    end

    test "links an existing channel to the account", %{
      account: account,
      channel_a: channel_a,
      options: options
    } do
      assert :ok = Slack.set_account_channel(account, "company:C_A", options)
      assert Repo.reload(channel_a).account_id == account.id

      activity = Repo.get_by!(Activity, action: "account.slack_channel_changed", target_id: account.id)

      assert activity.metadata["previous_channels"] == []

      assert activity.metadata["channels"] == [
               %{"slack_app" => "company", "slack_channel_id" => "C_A"}
             ]
    end

    test "creates a new slack_channels row when the picked channel is not yet tracked", %{
      account: account,
      options: options
    } do
      assert :ok = Slack.set_account_channel(account, "community:C_NEW", options)

      channel = Repo.get_by!(Channel, slack_app: :community, channel_id: "C_NEW")
      assert channel.account_id == account.id
      assert channel.slack_app == :community
      assert channel.channel_name == "new-channel"
    end

    test "switching to a different channel unlinks the previous one", %{
      account: account,
      channel_a: channel_a,
      options: options
    } do
      {:ok, _} = Slack.update_channel_account(channel_a, account.id)

      assert :ok = Slack.set_account_channel(account, "community:C_NEW", options)

      assert Repo.reload(channel_a).account_id == nil

      new_channel = Repo.get_by!(Channel, slack_app: :community, channel_id: "C_NEW")

      assert new_channel.account_id == account.id
    end

    test "keeps the previous channel linked when the replacement cannot be saved", %{
      account: account,
      channel_a: channel_a
    } do
      {:ok, _channel} = Slack.update_channel_account(channel_a, account.id)

      invalid_options = [
        %{
          slack_app: :community,
          slack_channel_id: "C_INVALID",
          name: nil,
          is_shared: false,
          is_ext_shared: false
        }
      ]

      audit_count = Repo.aggregate(Activity, :count)

      assert {:error, %Ecto.Changeset{}} =
               Slack.set_account_channel(account, "community:C_INVALID", invalid_options)

      assert Repo.reload(channel_a).account_id == account.id
      assert Repo.get_by(Channel, slack_app: :community, channel_id: "C_INVALID") == nil
      assert Repo.aggregate(Activity, :count) == audit_count
    end

    test "passing nil unlinks the currently-linked channel", %{
      account: account,
      channel_a: channel_a,
      options: options
    } do
      {:ok, _} = Slack.update_channel_account(channel_a, account.id)

      assert :ok = Slack.set_account_channel(account, nil, options)
      assert Repo.reload(channel_a).account_id == nil

      activity = Repo.get_by!(Activity, action: "account.slack_channel_changed", target_id: account.id)

      assert activity.metadata["previous_channels"] == [
               %{"slack_app" => "company", "slack_channel_id" => "C_A"}
             ]

      assert activity.metadata["channels"] == []
    end

    test "passing an empty string unlinks the currently-linked channel", %{
      account: account,
      channel_a: channel_a,
      options: options
    } do
      {:ok, _} = Slack.update_channel_account(channel_a, account.id)

      assert :ok = Slack.set_account_channel(account, "", options)
      assert Repo.reload(channel_a).account_id == nil
    end

    test "returns {:error, :unknown_channel} for a value not in the options", %{
      account: account,
      options: options
    } do
      assert {:error, :unknown_channel} =
               Slack.set_account_channel(account, "company:C_NOT_IN_LIST", options)
    end

    test "does not record an audit event when the channel does not change", %{
      account: account,
      channel_a: channel_a,
      options: options
    } do
      {:ok, _channel} = Slack.update_channel_account(channel_a, account.id)

      audit_count = Repo.aggregate(Activity, :count)

      assert :ok = Slack.set_account_channel(account, "company:C_A", options)
      assert Repo.aggregate(Activity, :count) == audit_count
    end
  end

  defp insert_account!(overrides \\ %{}) do
    suffix = System.unique_integer([:positive])

    defaults = %{
      account_key: "test:#{suffix}",
      name: "Account #{suffix}",
      segment: :customer
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, overrides))
    |> Repo.insert!()
  end

  defp insert_slack_event(account, ts) do
    %Event{}
    |> Event.changeset(%{
      external_id: "slack:company:Ctest:#{ts}",
      source: "slack",
      kind: "slack_message",
      title: "Slack message #{ts}",
      occurred_at: ~U[2026-04-01 10:00:00Z],
      account_id: account.id,
      metadata: %{"slack_ts" => ts}
    })
    |> Repo.insert()
  end
end
