defmodule Tuist.Push.Workers.ThreadFinishedWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Push
  alias Tuist.Push.Workers.DeliveryWorker
  alias Tuist.Push.Workers.ThreadFinishedWorker
  alias Tuist.Repo
  alias Tuist.Threads.Thread
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    app_client_id = Ecto.UUID.generate()
    stub(Environment, :oauth_client_id, fn -> app_client_id end)
    stub(Environment, :apns_configured?, fn -> true end)
    stub(Environment, :app_url, fn opts -> "https://tuist.dev" <> Keyword.get(opts, :path, "") end)
    :ok
  end

  defp register(user, app, platform) do
    {:ok, client} =
      case app do
        "luft" -> {:ok, %{id: Clients.luft_client_id()}}
        "tuist" -> {:ok, Clients.public!()}
      end

    bearer = TokenGenerator.generate(:access_token, %Token{sub: to_string(user.id), client_id: client.id})

    Repo.insert!(%Token{
      type: "access_token",
      value: bearer,
      refresh_token: Ecto.UUID.generate(),
      client_id: client.id,
      sub: to_string(user.id),
      scope: ""
    })

    {:ok, session} = Push.oauth_session(bearer, user, [app])

    token =
      if platform == "android",
        do: Base.encode64(:crypto.strong_rand_bytes(32)),
        else: Base.encode16(:crypto.strong_rand_bytes(32))

    {:ok, installation} =
      Push.register(user, session, Ecto.UUID.generate(), %{platform: platform, token: token, environment: "production"})

    installation
  end

  test "tells the owner's Luft devices, not the Tuist app, where to open the thread" do
    owner = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: owner)
    account = Accounts.get_account_from_organization(organization)
    iphone = register(owner, "luft", "ios")
    mac = register(owner, "luft", "macos")
    register(owner, "tuist", "ios")
    register(other, "luft", "ios")

    thread =
      Repo.insert!(%Thread{
        account_id: account.id,
        owner_id: owner.id,
        request_id: Ecto.UUID.generate(),
        request_hash: :crypto.strong_rand_bytes(32),
        goal: "The login flow loops; my staging token is abc123",
        provider: "chatgpt",
        model: "gpt",
        title: "Fix the login flow",
        agent_status: "idle"
      })

    assert :ok = perform_job(ThreadFinishedWorker, %{"thread_id" => thread.id, "status" => "idle"})

    payloads = Map.new(all_enqueued(worker: DeliveryWorker), &{&1.args["registration_id"], &1.args["payload"]})
    assert payloads |> Map.keys() |> Enum.sort() == Enum.sort([iphone.id, mac.id])

    target = %{
      "url" => "https://tuist.dev/luft/threads/#{thread.id}",
      "account" => account.name,
      "user" => Accounts.get_user_by_id(owner.id).account.name,
      "thread_id" => thread.id
    }

    assert payloads[iphone.id] ==
             Map.put(target, "aps", %{
               "alert" => %{"title" => "Fix the login flow", "body" => "Replied. Tap to read it."},
               "sound" => "default",
               "thread-id" => thread.id
             })

    assert payloads[mac.id] == payloads[iphone.id]
  end

  test "shows the first message as the title only once the agent renamed the thread" do
    owner = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(owner)
    iphone = register(owner, "luft", "ios")
    goal = "The login flow loops; my staging token is abc123 " <> String.duplicate("x", 100)

    thread =
      Repo.insert!(%Thread{
        account_id: account.id,
        owner_id: owner.id,
        request_id: Ecto.UUID.generate(),
        request_hash: :crypto.strong_rand_bytes(32),
        goal: goal,
        provider: "chatgpt",
        model: "gpt",
        title: String.slice(goal, 0, 80),
        agent_status: "failed"
      })

    assert :ok = perform_job(ThreadFinishedWorker, %{"thread_id" => thread.id, "status" => "failed"})

    assert [%{args: %{"registration_id" => registration_id, "payload" => payload}}] =
             all_enqueued(worker: DeliveryWorker)

    assert registration_id == iphone.id
    assert payload["aps"]["alert"]["title"] == "Your thread"
  end

  test "stays quiet about a thread snoozed until later, and reminds its owner when the snooze ends" do
    owner = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(owner)
    register(owner, "luft", "ios")

    thread =
      Repo.insert!(%Thread{
        account_id: account.id,
        owner_id: owner.id,
        request_id: Ecto.UUID.generate(),
        request_hash: :crypto.strong_rand_bytes(32),
        goal: "Fix the login flow",
        provider: "chatgpt",
        model: "gpt",
        title: "Fix the login flow",
        agent_status: "idle",
        snoozed_until: DateTime.utc_now() |> DateTime.add(1, :hour) |> DateTime.truncate(:second)
      })

    assert :ok = perform_job(ThreadFinishedWorker, %{"thread_id" => thread.id, "status" => "idle"})
    assert all_enqueued(worker: DeliveryWorker) == []

    assert :ok = perform_job(ThreadFinishedWorker, %{"thread_id" => thread.id, "status" => "snooze_ended"})

    assert [%{args: %{"payload" => %{"aps" => %{"alert" => %{"body" => "Your snooze is over. Tap to pick it up."}}}}}] =
             all_enqueued(worker: DeliveryWorker)
  end
end
