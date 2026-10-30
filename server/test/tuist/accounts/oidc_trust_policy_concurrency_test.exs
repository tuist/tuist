defmodule Tuist.Accounts.OIDCTrustPolicyConcurrencyTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Accounts
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    user = AccountsFixtures.user_fixture()

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        Repo.delete!(user.account)
        Repo.delete!(user)
      after
        Sandbox.checkin(Repo)
      end
    end)

    %{account: user.account}
  end

  test "concurrent creation at nineteen policies cannot exceed the account limit", %{account: account} do
    attrs = %{
      name: "Workload",
      issuer: "https://identity.example/tenant",
      jwks_url: "https://keys.example/jwks",
      audience: "tuist",
      claims: %{"sub" => "service:production"}
    }

    for index <- 1..19 do
      assert {:ok, _} = Accounts.create_oidc_trust_policy(account, %{attrs | name: "Policy #{index}"})
    end

    parent = self()

    first =
      database_task(fn ->
        Repo.transaction(fn ->
          {:ok, policy} = Accounts.create_oidc_trust_policy(account, %{attrs | name: "Twentieth"})
          send(parent, :twentieth_policy_uncommitted)

          receive do
            :commit -> policy
          after
            10_000 -> Repo.rollback(:commit_timeout)
          end
        end)
      end)

    try do
      assert_receive :twentieth_policy_uncommitted, 5_000

      second =
        database_task(fn ->
          %{rows: [[backend_pid]]} = Repo.query!("SELECT pg_backend_pid()")
          send(parent, {:competing_creation_started, backend_pid})
          Accounts.create_oidc_trust_policy(account, %{attrs | name: "Overflow"})
        end)

      try do
        assert_receive {:competing_creation_started, backend_pid}, 5_000
        assert wait_until_blocked(backend_pid, 500)
        send(first.pid, :commit)

        assert {:ok, policy} = Task.await(first, 5_000)
        assert policy.name == "Twentieth"
        assert {:error, changeset} = Task.await(second, 5_000)
        assert {"cannot exceed 20 trust policies per account", _} = changeset.errors[:name]
        policies = Accounts.list_oidc_trust_policies(account)
        assert length(policies) == 20
        refute Enum.any?(policies, &(&1.name == "Overflow"))
      after
        Task.shutdown(second, :brutal_kill)
      end
    after
      send(first.pid, :commit)
      Task.shutdown(first, :brutal_kill)
    end
  end

  defp database_task(function) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        function.()
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp wait_until_blocked(_backend_pid, 0), do: false

  defp wait_until_blocked(backend_pid, attempts) do
    case Repo.query!("SELECT cardinality(pg_blocking_pids($1)) > 0", [backend_pid]) do
      %{rows: [[true]]} ->
        true

      %{rows: [[false]]} ->
        Process.sleep(10)
        wait_until_blocked(backend_pid, attempts - 1)
    end
  end
end
