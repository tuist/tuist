defmodule Tuist.Accounts.PasswordResetConcurrencyTest do
  use ExUnit.Case, async: false
  use TuistTestSupport.Cases.LiveCase

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Accounts
  alias Tuist.Accounts.UserToken
  alias Tuist.Environment
  alias Tuist.Repo

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    user = user_fixture()
    stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)
    parent = self()

    stub(Bamboo.TestAdapter, :deliver, fn email, config ->
      send(parent, {:reset_email, email})
      Mimic.call_original(Bamboo.TestAdapter, :deliver, [email, config])
    end)

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.delete_all(from(t in UserToken, where: t.user_id == ^user.id))
      Repo.delete!(user.account)
      Repo.delete!(user)
      Sandbox.checkin(Repo)
    end)

    %{user: user}
  end

  test "concurrent requests issue one email and one active reset link", %{user: user} do
    concurrent(fn ->
      Accounts.deliver_user_reset_password_instructions(%{
        user: user,
        reset_password_url: &"https://example.com/users/reset_password/#{&1}"
      })
    end)

    assert_receive {:reset_email, _}
    refute_receive {:reset_email, _}

    assert Repo.aggregate(from(t in UserToken, where: t.user_id == ^user.id and t.context == "reset_password"), :count) ==
             1
  end

  test "concurrent submissions consume a reset link only once", %{user: user} do
    {token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    results = concurrent(fn -> Accounts.reset_user_password(token, %{password: "new concurrent password"}) end)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :invalid_token})) == 7
    refute Repo.get_by(UserToken, user_id: user.id)
    assert {:ok, _} = Accounts.get_user_by_email_and_password(user.email, "new concurrent password")
  end

  defp concurrent(fun) do
    parent = self()

    tasks =
      for _ <- 1..8 do
        Task.async(fn ->
          send(parent, {:ready, self()})
          receive do: (:go -> :ok)
          # Independent transactions model requests routed to different replicas.
          :ok = Sandbox.checkout(Repo, sandbox: false)

          try do
            fun.()
          after
            Sandbox.checkin(Repo)
          end
        end)
      end

    for _ <- tasks, do: assert_receive({:ready, _}, 5_000)
    Enum.each(tasks, &send(&1.pid, :go))
    Enum.map(tasks, &Task.await(&1, 10_000))
  end
end
