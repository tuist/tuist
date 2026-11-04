defmodule Tuist.Accounts.AISubscriptionsConcurrencyTest do
  use ExUnit.Case, async: false
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Accounts.AISubscriptions
  alias Tuist.Accounts.UserAISubscription
  alias Tuist.Environment
  alias Tuist.Repo

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    user = user_fixture()
    stub(Environment, :chatgpt_client_id, fn -> "app_test_client" end)

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.delete_all(from(s in UserAISubscription, where: s.user_id == ^user.id))
      Repo.delete!(user.account)
      Repo.delete!(user)
      Sandbox.checkin(Repo)
    end)

    %{user: user}
  end

  test "concurrent reads of an expired ChatGPT token refresh it once", %{user: user} do
    insert_expired_chatgpt(user)
    parent = self()

    stub(Req, :post, fn opts ->
      send(parent, {:refresh, opts[:form][:refresh_token]})
      # Hold the exchange open so the other readers queue behind it.
      Process.sleep(100)

      {:ok,
       %Req.Response{
         status: 200,
         body: %{"access_token" => "access-2", "refresh_token" => "refresh-2", "expires_in" => 3600}
       }}
    end)

    results = concurrent(fn -> AISubscriptions.credentials(user, :chatgpt) end)

    assert Enum.all?(results, &(&1 == {:ok, %{provider: :chatgpt, access_token: "access-2"}}))
    assert_received {:refresh, "refresh-1"}
    refute_received {:refresh, _}

    assert %{refresh_token: "refresh-2"} = Repo.get_by!(UserAISubscription, user_id: user.id, provider: :chatgpt)
  end

  test "a disconnect during a refresh does not wait for OpenAI and is not undone", %{user: user} do
    insert_expired_chatgpt(user)
    parent = self()

    stub(Req, :post, fn _opts ->
      send(parent, :refreshing)
      Process.sleep(500)
      {:ok, %Req.Response{status: 200, body: %{"access_token" => "access-2", "expires_in" => 3600}}}
    end)

    refresh = Task.async(fn -> in_own_transaction(fn -> AISubscriptions.credentials(user, :chatgpt) end) end)
    assert_receive :refreshing

    # No lock is held across the OpenAI call, so the disconnect completes while it is in flight.
    assert :ok = AISubscriptions.disconnect(user, :chatgpt)
    assert Task.yield(refresh, 0) == nil

    assert {:error, :not_connected} = Task.await(refresh)
    refute Repo.get_by(UserAISubscription, user_id: user.id, provider: :chatgpt)
  end

  test "a disconnect during a sign-in poll is not undone by the approval", %{user: user} do
    parent = self()

    stub(Req, :post, fn opts ->
      case opts[:url] do
        "https://auth.openai.com/api/accounts/deviceauth/usercode" ->
          {:ok,
           %Req.Response{status: 200, body: %{"device_auth_id" => "dev-1", "user_code" => "ABCD-1234", "interval" => 5}}}

        "https://auth.openai.com/api/accounts/deviceauth/token" ->
          send(parent, :polling)
          Process.sleep(500)
          {:ok, %Req.Response{status: 200, body: %{"authorization_code" => "code-1", "code_verifier" => "verifier-1"}}}

        "https://auth.openai.com/oauth/token" ->
          {:ok,
           %Req.Response{
             status: 200,
             body: %{"access_token" => "access-1", "refresh_token" => "refresh-1", "expires_in" => 3600}
           }}
      end
    end)

    {:ok, %{login_id: login_id}} = AISubscriptions.start_chatgpt(user)

    Repo.update_all(from(s in UserAISubscription, where: s.user_id == ^user.id),
      set: [next_poll_at: DateTime.add(DateTime.utc_now(:second), -1, :second)]
    )

    poll = Task.async(fn -> in_own_transaction(fn -> AISubscriptions.poll_chatgpt(user, login_id) end) end)
    assert_receive :polling
    assert :ok = AISubscriptions.disconnect(user, :chatgpt)

    assert {:error, :not_found} = Task.await(poll)
    refute Repo.get_by(UserAISubscription, user_id: user.id, provider: :chatgpt)
  end

  defp insert_expired_chatgpt(user) do
    %UserAISubscription{user_id: user.id, provider: :chatgpt}
    |> UserAISubscription.changeset(%{
      access_token: "access-1",
      refresh_token: "refresh-1",
      expires_at: DateTime.add(DateTime.utc_now(:second), -10, :second)
    })
    |> Repo.insert!()
  end

  defp concurrent(fun) do
    parent = self()

    tasks =
      for _ <- 1..8 do
        Task.async(fn ->
          send(parent, {:ready, self()})
          receive do: (:go -> :ok)
          in_own_transaction(fun)
        end)
      end

    pids = for _ <- tasks, do: receive(do: ({:ready, pid} -> pid))
    Enum.each(pids, &send(&1, :go))
    Task.await_many(tasks, 15_000)
  end

  # Independent connections model requests routed to different replicas.
  defp in_own_transaction(fun) do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    try do
      fun.()
    after
      Sandbox.checkin(Repo)
    end
  end
end
