defmodule Atlas.Slack.APITest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Slack.API
  alias Atlas.Slack.Bot

  setup :verify_on_exit!

  setup do
    stub(Bot, :bot_token, fn
      :company -> "xoxb-test"
      :community -> "xoxb-community"
    end)

    stub(Bot, :configured?, fn _app_key -> true end)

    :ok
  end

  defp slack_response(body) do
    {:ok, %Req.Response{status: 200, body: body}}
  end

  describe "get_user_info/1" do
    test "returns a normalized profile on success" do
      Req
      |> expect(:get, fn url, opts ->
        assert url == "https://slack.com/api/users.info"
        assert opts[:auth] == {:bearer, "xoxb-test"}
        assert opts[:params] == [user: "U123"]

        slack_response(%{
          "ok" => true,
          "user" => %{
            "id" => "U123",
            "name" => "alice",
            "real_name" => "Alice Internal",
            "is_bot" => false,
            "is_stranger" => false,
            "profile" => %{
              "display_name" => "alice",
              "real_name" => "Alice Internal",
              "email" => "Alice@TUist.dev",
              "image_72" => "https://avatars.example.com/alice-72.png",
              "image_48" => "https://avatars.example.com/alice-48.png"
            }
          }
        })
      end)

      assert {:ok, profile} = API.get_user_info(:company, "U123")
      assert profile.slack_user_id == "U123"
      assert profile.name == "alice"
      assert profile.real_name == "Alice Internal"
      assert profile.display_name == "alice"
      assert profile.email == "alice@tuist.dev"
      assert profile.avatar_url == "https://avatars.example.com/alice-72.png"
      assert profile.is_bot == false
      assert profile.is_external == false
    end

    test "uses the requested app token" do
      Req
      |> expect(:get, fn _url, opts ->
        assert opts[:auth] == {:bearer, "xoxb-community"}

        slack_response(%{
          "ok" => true,
          "user" => %{"id" => "U123", "name" => "alice", "profile" => %{}}
        })
      end)

      assert {:ok, profile} = API.get_user_info(:community, "U123")
      assert profile.slack_user_id == "U123"
    end

    test "marks Slack Connect strangers as external" do
      Req
      |> expect(:get, fn _url, _opts ->
        slack_response(%{
          "ok" => true,
          "user" => %{
            "id" => "U999",
            "name" => "external",
            "is_stranger" => true,
            "is_bot" => false,
            "profile" => %{"image_72" => "https://x.example/72.png"}
          }
        })
      end)

      assert {:ok, profile} = API.get_user_info(:company, "U999")
      assert profile.is_external == true
    end

    test "marks bot users as bots" do
      Req
      |> expect(:get, fn _url, _opts ->
        slack_response(%{
          "ok" => true,
          "user" => %{"id" => "B1", "name" => "atlas-bot", "is_bot" => true, "profile" => %{}}
        })
      end)

      assert {:ok, profile} = API.get_user_info(:company, "B1")
      assert profile.is_bot == true
      assert profile.is_external == false
    end

    test "falls back through avatar sizes when image_72 is missing" do
      Req
      |> expect(:get, fn _url, _opts ->
        slack_response(%{
          "ok" => true,
          "user" => %{
            "id" => "U1",
            "name" => "n",
            "profile" => %{"image_48" => "https://x/48.png"}
          }
        })
      end)

      assert {:ok, profile} = API.get_user_info(:company, "U1")
      assert profile.avatar_url == "https://x/48.png"
    end

    test "uses image_192 when 72 and 48 are missing" do
      Req
      |> expect(:get, fn _url, _opts ->
        slack_response(%{
          "ok" => true,
          "user" => %{
            "id" => "U1",
            "name" => "n",
            "profile" => %{"image_192" => "https://x/192.png"}
          }
        })
      end)

      assert {:ok, profile} = API.get_user_info(:company, "U1")
      assert profile.avatar_url == "https://x/192.png"
    end

    test "treats blank display_name as nil" do
      Req
      |> expect(:get, fn _url, _opts ->
        slack_response(%{
          "ok" => true,
          "user" => %{
            "id" => "U1",
            "name" => "n",
            "profile" => %{"display_name" => "  "}
          }
        })
      end)

      assert {:ok, profile} = API.get_user_info(:company, "U1")
      assert profile.display_name == nil
    end

    test "uses real_name from the user object when profile is missing one" do
      Req
      |> expect(:get, fn _url, _opts ->
        slack_response(%{
          "ok" => true,
          "user" => %{
            "id" => "U1",
            "name" => "n",
            "real_name" => "Top-level Real Name",
            "profile" => %{}
          }
        })
      end)

      assert {:ok, profile} = API.get_user_info(:company, "U1")
      assert profile.real_name == "Top-level Real Name"
    end

    test "handles missing profile entirely" do
      Req
      |> expect(:get, fn _url, _opts ->
        slack_response(%{"ok" => true, "user" => %{"id" => "U1", "name" => "n"}})
      end)

      assert {:ok, profile} = API.get_user_info(:company, "U1")
      assert profile.slack_user_id == "U1"
      assert profile.name == "n"
      assert profile.real_name == nil
      assert profile.display_name == nil
      assert profile.avatar_url == nil
      assert profile.is_bot == false
      assert profile.is_external == false
    end

    test "uses the requested user_id when the response omits id" do
      Req
      |> expect(:get, fn _url, _opts ->
        slack_response(%{"ok" => true, "user" => %{"name" => "n", "profile" => %{}}})
      end)

      assert {:ok, profile} = API.get_user_info(:company, "U_FALLBACK")
      assert profile.slack_user_id == "U_FALLBACK"
    end

    test "returns the Slack error code when ok=false" do
      Req
      |> expect(:get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => "user_not_found"}}}
      end)

      assert {:error, "user_not_found"} = API.get_user_info(:company, "U123")
    end

    test "returns an :unexpected_response tuple on non-200" do
      Req
      |> expect(:get, fn _url, _opts ->
        {:ok, %Req.Response{status: 500, body: %{}}}
      end)

      assert {:error, {:unexpected_response, 500, _}} = API.get_user_info(:company, "U123")
    end

    test "propagates Req transport errors" do
      Req
      |> expect(:get, fn _url, _opts -> {:error, %Req.TransportError{reason: :nxdomain}} end)

      assert {:error, %Req.TransportError{}} = API.get_user_info(:company, "U123")
    end
  end

  describe "get_permalink/2" do
    test "returns the permalink on success" do
      Req
      |> expect(:get, fn url, opts ->
        assert url == "https://slack.com/api/chat.getPermalink"
        assert opts[:params] == [channel: "C123", message_ts: "1710000000.100000"]

        slack_response(%{
          "ok" => true,
          "permalink" => "https://acme.slack.com/archives/C123/p1710000000100000"
        })
      end)

      assert {:ok, "https://acme.slack.com/archives/C123/p1710000000100000"} =
               API.get_permalink(:company, "C123", "1710000000.100000")
    end

    test "returns the Slack error code when ok=false" do
      Req
      |> expect(:get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => "channel_not_found"}}}
      end)

      assert {:error, "channel_not_found"} =
               API.get_permalink(:company, "Cmissing", "1.0")
    end
  end

  describe "list_thread_messages/3" do
    test "returns normalized thread messages on success" do
      Req
      |> expect(:get, fn url, opts ->
        assert url == "https://slack.com/api/conversations.replies"
        assert opts[:params][:channel] == "C123"
        assert opts[:params][:ts] == "1710000000.100000"
        assert opts[:params][:inclusive] == true
        assert opts[:params][:limit] == 1000

        slack_response(%{
          "ok" => true,
          "messages" => [
            %{
              "user" => "U123",
              "text" => "First question",
              "ts" => "1710000000.100000",
              "thread_ts" => "1710000000.100000"
            },
            %{
              "bot_id" => "B_ATLAS",
              "username" => "Atlas",
              "subtype" => "bot_message",
              "text" => "First answer",
              "ts" => "1710000001.100000",
              "thread_ts" => "1710000000.100000"
            }
          ]
        })
      end)

      assert {:ok, [first, second]} = API.list_thread_messages(:company, "C123", "1710000000.100000")

      assert first.user_id == "U123"
      assert first.text == "First question"
      assert first.thread_ts == "1710000000.100000"
      assert second.bot_id == "B_ATLAS"
      assert second.username == "Atlas"
      assert second.subtype == "bot_message"
    end

    test "returns the Slack error code when ok=false" do
      Req
      |> expect(:get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => "thread_not_found"}}}
      end)

      assert {:error, "thread_not_found"} =
               API.list_thread_messages(:company, "C123", "1710000000.100000")
    end
  end

  describe "list_channels/1" do
    test "returns an error without calling Req when the bot token is not configured" do
      Bot
      |> stub(:configured?, fn _app_key -> false end)

      Req
      |> reject(:get, 2)

      assert {:error, :slack_bot_not_configured} = API.list_channels(:company)
    end

    test "normalizes Slack Connect, shared, and member flags" do
      Req
      |> expect(:get, fn url, opts ->
        assert url == "https://slack.com/api/conversations.list"
        assert opts[:params][:exclude_archived] == true
        assert opts[:params][:limit] == 1000

        slack_response(%{
          "ok" => true,
          "channels" => [
            %{
              "id" => "C1",
              "name" => "support",
              "is_shared" => false,
              "is_ext_shared" => false,
              "is_member" => true,
              "is_archived" => false
            },
            %{
              "id" => "C2",
              "name" => "acme-tuist",
              "is_shared" => true,
              "is_ext_shared" => true,
              "is_member" => true,
              "is_archived" => false
            }
          ]
        })
      end)

      assert {:ok, [internal, connect]} = API.list_channels(:company)

      assert internal.slack_channel_id == "C1"
      assert internal.slack_app == :company
      assert internal.is_shared == false
      assert internal.is_ext_shared == false

      assert connect.slack_channel_id == "C2"
      assert connect.slack_app == :company
      assert connect.is_shared == true
      assert connect.is_ext_shared == true
    end

    test "filters archived channels even if Slack still returns them" do
      Req
      |> expect(:get, fn _url, _opts ->
        slack_response(%{
          "ok" => true,
          "channels" => [
            %{"id" => "C1", "name" => "current", "is_archived" => false},
            %{"id" => "C2", "name" => "old", "is_archived" => true}
          ]
        })
      end)

      assert {:ok, [%{slack_channel_id: "C1"}]} = API.list_channels(:company)
    end

    test "returns the Slack error when ok=false" do
      Req
      |> expect(:get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => "missing_scope"}}}
      end)

      assert {:error, "missing_scope"} = API.list_channels(:company)
    end
  end

  describe "unfurl_link/4" do
    test "POSTs the unfurl payload to chat.unfurl with the bot token" do
      Req
      |> expect(:post, fn url, opts ->
        assert url == "https://slack.com/api/chat.unfurl"
        assert opts[:auth] == {:bearer, "xoxb-test"}

        assert opts[:json] == %{
                 channel: "C123",
                 ts: "1710000500.000100",
                 unfurls: %{
                   "https://atlas.example.com/accounts/abc" => %{
                     "title" => "Contoso",
                     "title_link" => "https://atlas.example.com/accounts/abc"
                   }
                 }
               }

        slack_response(%{"ok" => true})
      end)

      assert :ok =
               API.unfurl_link(:company, "C123", "1710000500.000100", %{
                 "https://atlas.example.com/accounts/abc" => %{
                   "title" => "Contoso",
                   "title_link" => "https://atlas.example.com/accounts/abc"
                 }
               })
    end

    test "returns the Slack error code when ok=false" do
      Req
      |> expect(:post, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => "cannot_unfurl_url"}}}
      end)

      assert {:error, "cannot_unfurl_url"} =
               API.unfurl_link(:company, "C123", "1.0", %{"https://x" => %{"text" => "hi"}})
    end

    test "returns an error without calling Req when the bot token is not configured" do
      Bot
      |> stub(:configured?, fn _app_key -> false end)

      Req
      |> reject(:post, 2)

      assert {:error, :slack_bot_not_configured} =
               API.unfurl_link(:company, "C123", "1.0", %{"https://x" => %{"text" => "hi"}})
    end
  end

  describe "post_message/5" do
    test "posts a threaded Block Kit message" do
      blocks = [%{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => "Hello"}}]

      Req
      |> expect(:post, fn url, opts ->
        assert url == "https://slack.com/api/chat.postMessage"
        assert opts[:auth] == {:bearer, "xoxb-test"}

        assert opts[:json] == %{
                 channel: "C123",
                 text: "Hello",
                 blocks: blocks,
                 thread_ts: "1710000500.000100"
               }

        slack_response(%{"ok" => true, "ts" => "1710000501.000200"})
      end)

      assert {:ok, %{"ts" => "1710000501.000200"}} =
               API.post_message(:company, "C123", "Hello", blocks, thread_ts: "1710000500.000100")
    end

    test "posts with a client message id for idempotent retries" do
      Req
      |> expect(:post, fn _url, opts ->
        assert opts[:json].client_msg_id == "candidate-123"
        slack_response(%{"ok" => true, "ts" => "1710000501.000200"})
      end)

      assert {:ok, %{"ts" => "1710000501.000200"}} =
               API.post_message(:company, "C123", "Hello", [], client_msg_id: "candidate-123")
    end

    test "posts durable metadata used to reconcile an ambiguous retry" do
      metadata = %{event_type: "atlas_brief", event_payload: %{key: "brief-123"}}

      Req
      |> expect(:post, fn _url, opts ->
        assert opts[:json].metadata == metadata
        slack_response(%{"ok" => true, "ts" => "1710000501.000200"})
      end)

      assert {:ok, %{"ts" => "1710000501.000200"}} =
               API.post_message(:company, "C123", "Hello", [], metadata: metadata)
    end

    test "returns the Slack error code when posting fails" do
      Req
      |> expect(:post, fn _url, _opts ->
        slack_response(%{"ok" => false, "error" => "not_in_channel"})
      end)

      assert {:error, "not_in_channel"} = API.post_message(:company, "C123", "Hello", [])
    end
  end

  describe "find_message_by_metadata/4" do
    test "finds the accepted message for a durable notification key" do
      Req
      |> expect(:get, fn url, opts ->
        assert url == "https://slack.com/api/conversations.history"
        assert opts[:params] == [channel: "C123", include_all_metadata: true, limit: 100]

        slack_response(%{
          "ok" => true,
          "messages" => [
            %{
              "ts" => "1710000501.000200",
              "metadata" => %{
                "event_type" => "atlas_brief",
                "event_payload" => %{"key" => "brief-123"}
              }
            }
          ]
        })
      end)

      assert {:ok, %{"ts" => "1710000501.000200"}} =
               API.find_message_by_metadata(:company, "C123", "atlas_brief", "brief-123")
    end
  end

  describe "update_message/5" do
    test "updates a Block Kit message" do
      blocks = [%{"type" => "section", "text" => %{"type" => "mrkdwn", "text" => "Updated"}}]

      Req
      |> expect(:post, fn url, opts ->
        assert url == "https://slack.com/api/chat.update"
        assert opts[:auth] == {:bearer, "xoxb-test"}

        assert opts[:json] == %{
                 channel: "C123",
                 ts: "1710000501.000200",
                 text: "Updated",
                 blocks: blocks
               }

        slack_response(%{"ok" => true})
      end)

      assert {:ok, %{"ok" => true}} =
               API.update_message(:company, "C123", "1710000501.000200", "Updated", blocks)
    end

    test "preserves durable message metadata explicitly" do
      metadata = %{event_type: "atlas_brief", event_payload: %{key: "brief-123"}}

      Req
      |> expect(:post, fn _url, opts ->
        assert opts[:json].metadata == metadata
        slack_response(%{"ok" => true})
      end)

      assert {:ok, %{"ok" => true}} =
               API.update_message(:company, "C123", "1710000501.000200", "Updated", [], metadata: metadata)
    end

    test "returns the Slack error code when updating fails" do
      Req
      |> expect(:post, fn _url, _opts ->
        slack_response(%{"ok" => false, "error" => "message_not_found"})
      end)

      assert {:error, "message_not_found"} =
               API.update_message(:company, "C123", "1710000501.000200", "Updated", [])
    end
  end

  describe "set_assistant_thread_status/5" do
    test "sets an assistant status for a thread" do
      Req
      |> expect(:post, fn url, opts ->
        assert url == "https://slack.com/api/assistant.threads.setStatus"
        assert opts[:auth] == {:bearer, "xoxb-test"}

        assert opts[:json] == %{
                 channel_id: "C123",
                 thread_ts: "1710000500.000100",
                 status: "is working on this request...",
                 loading_messages: ["Checking Atlas context"]
               }

        slack_response(%{"ok" => true})
      end)

      assert :ok =
               API.set_assistant_thread_status(
                 :company,
                 "C123",
                 "1710000500.000100",
                 "is working on this request...",
                 loading_messages: ["Checking Atlas context"]
               )
    end

    test "returns the Slack error code when setting status fails" do
      Req
      |> expect(:post, fn _url, _opts ->
        slack_response(%{"ok" => false, "error" => "missing_scope"})
      end)

      assert {:error, "missing_scope"} =
               API.set_assistant_thread_status(:company, "C123", "1710000500.000100", "is working")
    end

    test "omits empty loading messages so Slack status clearing stays valid" do
      Req
      |> expect(:post, fn url, opts ->
        assert url == "https://slack.com/api/assistant.threads.setStatus"
        assert opts[:auth] == {:bearer, "xoxb-test"}

        assert opts[:json] == %{
                 channel_id: "C123",
                 thread_ts: "1710000500.000100",
                 status: ""
               }

        slack_response(%{"ok" => true})
      end)

      assert :ok =
               API.set_assistant_thread_status(
                 :company,
                 "C123",
                 "1710000500.000100",
                 "",
                 loading_messages: []
               )
    end
  end

  describe "streaming messages" do
    test "starts a native Slack stream" do
      Req
      |> expect(:post, fn url, opts ->
        assert url == "https://slack.com/api/chat.startStream"
        assert opts[:auth] == {:bearer, "xoxb-test"}

        assert opts[:json] == %{
                 channel: "C123",
                 thread_ts: "1710000500.000100",
                 markdown_text: "Hello",
                 recipient_user_id: "U123",
                 recipient_team_id: "T123"
               }

        slack_response(%{"ok" => true, "ts" => "1710000501.000200"})
      end)

      assert {:ok, %{"ts" => "1710000501.000200"}} =
               API.start_stream(:company, "C123", "1710000500.000100",
                 markdown_text: "Hello",
                 recipient_user_id: "U123",
                 recipient_team_id: "T123"
               )
    end

    test "appends to a native Slack stream" do
      Req
      |> expect(:post, fn url, opts ->
        assert url == "https://slack.com/api/chat.appendStream"
        assert opts[:auth] == {:bearer, "xoxb-test"}

        assert opts[:json] == %{
                 channel: "C123",
                 ts: "1710000501.000200",
                 markdown_text: " world"
               }

        slack_response(%{"ok" => true, "ts" => "1710000501.000200"})
      end)

      assert {:ok, %{"ts" => "1710000501.000200"}} =
               API.append_stream(:company, "C123", "1710000501.000200", " world")
    end

    test "stops a native Slack stream" do
      Req
      |> expect(:post, fn url, opts ->
        assert url == "https://slack.com/api/chat.stopStream"
        assert opts[:auth] == {:bearer, "xoxb-test"}

        assert opts[:json] == %{
                 channel: "C123",
                 ts: "1710000501.000200"
               }

        slack_response(%{"ok" => true, "ts" => "1710000501.000200"})
      end)

      assert {:ok, %{"ts" => "1710000501.000200"}} =
               API.stop_stream(:company, "C123", "1710000501.000200")
    end

    test "returns the Slack error code when streaming fails" do
      Req
      |> expect(:post, fn _url, _opts ->
        slack_response(%{"ok" => false, "error" => "message_not_in_streaming_state"})
      end)

      assert {:error, "message_not_in_streaming_state"} =
               API.append_stream(:company, "C123", "1710000501.000200", " world")
    end
  end

  describe "get_user_display_name/1" do
    test "delegates to get_user_info and picks the best display name" do
      Req
      |> expect(:get, fn _url, _opts ->
        slack_response(%{
          "ok" => true,
          "user" => %{
            "id" => "U1",
            "name" => "n",
            "profile" => %{"display_name" => "alice", "real_name" => "Alice"}
          }
        })
      end)

      assert {:ok, "alice"} = API.get_user_display_name(:company, "U1")
    end

    test "returns the error code when the lookup fails" do
      Req
      |> expect(:get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => "user_not_found"}}}
      end)

      assert {:error, "user_not_found"} = API.get_user_display_name(:company, "U999")
    end
  end
end
