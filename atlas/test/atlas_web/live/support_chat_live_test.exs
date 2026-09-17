defmodule AtlasWeb.SupportChatLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  import Phoenix.LiveViewTest

  alias Atlas.Support
  alias Atlas.Users.User
  alias AtlasWeb.SupportChatRateLimit

  test "lets a visitor start and continue an embedded support chat", %{conn: conn} do
    stub(SupportChatRateLimit, :check, fn _ip, _email -> :ok end)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/support/chat?#{%{"source" => "https://tuist.dev/docs/cache", "parent_origin" => "https://tuist.dev"}}"
      )

    assert has_element?(view, "#support-chat")
    assert has_element?(view, "#support-chat [data-part='title']")
    assert has_element?(view, "#support-chat [data-part='response-time']")
    assert has_element?(view, "#support-chat-close")
    assert has_element?(view, "#support-chat-close[data-parent-origin='https://tuist.dev']")
    assert has_element?(view, "#support-chat-form")
    assert has_element?(view, "#support-chat-name")
    assert has_element?(view, "#support-chat-email")

    view
    |> form("#support-chat-form", %{
      "chat" => %{
        "name" => "Maya Chen",
        "email" => "maya@example.com",
        "body" => "Could you help us with this cache upload?",
        "source_url" => "https://tuist.dev/docs/cache"
      }
    })
    |> render_submit()

    assert_push_event(view, "support-chat-session", %{conversation: _conversation})
    assert has_element?(view, "#support-chat-messages", "Could you help us with this cache upload?")
    assert has_element?(view, "#support-chat-form input[type='hidden'][name='chat[email]']")
    assert has_element?(view, "#support-chat-email-verification")
    assert has_element?(view, "#support-chat-close[data-parent-origin='https://tuist.dev']")

    thread = Support.list_threads(query: "maya@example.com") |> elem(0) |> List.first()

    view
    |> form("#support-chat-form", %{
      "chat" => %{
        "name" => "Maya Chen",
        "email" => "maya@example.com",
        "body" => "The upload is still blocked.",
        "source_url" => "https://tuist.dev/docs/cache"
      }
    })
    |> render_submit()

    assert length(Support.get_thread(thread.id).messages) == 2
    assert has_element?(view, "#support-chat-messages", "The upload is still blocked.")
    assert length(Registry.lookup(Atlas.PubSub, "support:thread:#{thread.id}")) == 1
  end

  test "shows a team reply in the chat before the email is confirmed", %{conn: conn} do
    stub(SupportChatRateLimit, :check, fn _ip, _email -> :ok end)

    {:ok, view, _html} = live(conn, ~p"/support/chat?#{%{"source" => "https://tuist.dev"}}")

    view
    |> form("#support-chat-form", %{
      "chat" => %{
        "email" => "maya@example.com",
        "body" => "Could you help us?",
        "source_url" => "https://tuist.dev"
      }
    })
    |> render_submit()

    [thread] = Support.list_threads(query: "maya@example.com") |> elem(0)
    agent = support_agent!()

    assert {:ok, %{message: reply}} = Support.reply(thread, %{"body" => "We are investigating this now."}, agent)
    assert reply.delivery_status == "delivered"
    assert reply.metadata["delivery_channel"] == "chat"

    assert has_element?(view, "#support-chat-messages [data-kind='outbound']", "We are investigating this now.")
  end

  test "shows the retry delay when the chat rate limit rejects a submission", %{conn: conn} do
    stub(SupportChatRateLimit, :check, fn _ip, _email -> {:error, 23} end)

    {:ok, view, _html} = live(conn, ~p"/support/chat")

    view
    |> form("#support-chat-form", %{
      "chat" => %{"email" => "maya@example.com", "body" => "Could you help us?"}
    })
    |> render_submit()

    assert has_element?(view, "#support-chat-retry-error", "Please wait 23 seconds before sending another message.")
  end

  defp support_agent! do
    suffix = System.unique_integer([:positive])

    %User{}
    |> User.changeset(%{email: "support-chat-agent-#{suffix}@tuist.dev", name: "Support Agent"})
    |> Atlas.Repo.insert!()
  end
end
