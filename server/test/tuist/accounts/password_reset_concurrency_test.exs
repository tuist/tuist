defmodule Tuist.Accounts.PasswordResetConcurrencyTest do
  use ExUnit.Case, async: false
  use TuistTestSupport.Cases.LiveCase

  import Ecto.Query
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Accounts
  alias Tuist.Accounts.UserMFA
  alias Tuist.Accounts.UserToken
  alias Tuist.Environment
  alias Tuist.Repo

  @endpoint TuistWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    user = user_fixture()
    stub(Environment, :mailing_from_address, fn -> "noreply@tuist.dev" end)
    stub(TuistWeb.RateLimit.Auth, :hit, fn _ -> {:allow, 1} end)
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

  test "concurrent reset consumption retains an enrolled factor", %{user: user} do
    enroll(user)
    {token, record} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(record)
    results = concurrent(fn -> Accounts.reset_user_password(token, %{password: "new concurrent password"}) end)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :invalid_token})) == 7
    assert UserMFA.enabled?(user)
    refute Repo.get_by(UserToken, user_id: user.id)
    assert user |> login("new concurrent password") |> redirected_to() == "/users/mfa"
  end

  for revocation <- [:reset, :disable] do
    @tag :mfa_issuance_race
    test "#{revocation} cannot be overtaken by a previously completed MFA challenge", %{user: user} do
      {confirmed, [login_code, disable_code | _]} = enroll(user)
      pending = login(user)
      revocation = prepare_revocation(unquote(revocation), user, confirmed)
      parent = self()

      issuance =
        independent(fn ->
          receive do: (:verify -> :ok)
          pending |> recycle() |> post("/users/mfa", %{"mfa_code" => login_code})
        end)

      stub(Accounts, :generate_user_session_token, fn user, auth ->
        if self() == issuance.pid do
          [[backend]] = Repo.query!("SELECT pg_backend_pid()").rows
          send(parent, {:issuance_paused, self(), backend})
          receive do: (:issue -> :ok)
        end

        Mimic.call_original(Accounts, :generate_user_session_token, [user, auth])
      end)

      send(issuance.pid, :verify)
      assert_receive {:issuance_paused, issuer, backend}, 5_000
      revoker = independent(fn -> revoke(unquote(revocation), user, revocation, disable_code) end)

      # Before the fix revocation finishes in this gap. With atomic issuance it
      # waits on the issuing transaction's user lock. Exercise either ordering.
      completed = wait_for_revocation_or_lock(revoker, backend)
      send(issuer, :issue)
      issued = Task.await(issuance, 10_000)
      if completed == :blocked, do: Task.await(revoker, 10_000)
      if unquote(revocation) == :reset, do: assert_redirect(revocation, "/users/log_in")

      assert Accounts.get_user_by_session_token(get_session(issued, :user_token)) == nil
      assert issued |> recycle() |> get("/#{user.account.name}/projects") |> redirected_to() == "/users/log_in"
    end
  end

  defp wait_for_revocation_or_lock(task, backend) do
    case Task.yield(task, 10) do
      {:ok, _} ->
        :completed

      nil ->
        [[blocked]] =
          fn ->
            Repo.query!("SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE $1 = ANY(pg_blocking_pids(pid)))", [backend]).rows
          end
          |> independent()
          |> Task.await()

        if blocked, do: :blocked, else: wait_for_revocation_or_lock(task, backend)
    end
  end

  defp prepare_revocation(:reset, user, _confirmed) do
    {token, record} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(record)
    {:ok, view, _} = live(build_conn(), "/users/reset_password/#{token}")
    view
  end

  defp prepare_revocation(:disable, _user, confirmed), do: confirmed

  defp revoke(:reset, _user, view, _code) do
    view
    |> form("#reset_password_form", %{
      "user" => %{"password" => "new concurrent password", "password_confirmation" => "new concurrent password"}
    })
    |> render_submit()
  end

  defp revoke(:disable, user, confirmed, code) do
    assert confirmed |> recycle() |> post("/users/settings/mfa/disable", %{"mfa_code" => code}) |> redirected_to() ==
             "/users/settings/mfa"

    refute UserMFA.enabled?(user)
  end

  defp login(user, password \\ valid_user_password()) do
    post(build_conn(), "/users/log_in", %{"user" => %{"email" => user.email, "password" => password}})
  end

  defp enroll(user) do
    enrollment = user |> login() |> recycle() |> post("/users/settings/mfa/enroll")
    factor = Repo.get_by!(UserMFA, user_id: user.id)
    code = NimbleTOTP.verification_code(factor.secret)
    confirmed = enrollment |> recycle() |> post("/users/settings/mfa/confirm", %{"mfa_code" => code})

    codes =
      confirmed
      |> html_response(200)
      |> Floki.parse_document!()
      |> Floki.find("#mfa-recovery-codes code")
      |> Enum.map(&Floki.text/1)

    {confirmed, codes}
  end

  defp independent(fun) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        fun.()
      after
        Sandbox.checkin(Repo)
      end
    end)
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
