defmodule Tuist.Sandboxes.WorkspacesTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.ProviderEnvironment
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Workspaces

  test "allocation persists its account-scoped replay key before boot and reuses its sandbox" do
    account = user_fixture().account
    key = Ecto.UUID.generate()

    expect(Sandboxes, :create_sandbox, fn actual, %{provider_environment_id: id} ->
      assert actual.id == account.id
      assert Repo.get!(ProviderEnvironment, id).external_key == "workspaces/#{key}"
      {:ok, Repo.insert!(%Sandbox{account_id: account.id, provider_environment_id: id, state: :running})}
    end)

    assert {:ok, sandbox} = Workspaces.ensure(account, key)
    assert {:ok, replay} = Workspaces.ensure(account, key)
    assert replay.id == sandbox.id
    assert Repo.aggregate(ProviderEnvironment, :count) == 1
  end

  test "sandbox lookup never crosses accounts or includes remote executors" do
    account = user_fixture().account
    stranger = user_fixture().account
    sandbox = Repo.insert!(%Sandbox{account_id: account.id, state: :running})
    assert {:ok, ^sandbox} = Workspaces.fetch(account, sandbox.id)
    assert {:error, :not_found} = Workspaces.fetch(stranger, sandbox.id)
    executor = Repo.insert!(%Sandbox{account_id: account.id, purpose: :remote_execution, state: :running})
    assert {:error, :not_found} = Workspaces.fetch(account, executor.id)
    assert {:error, :not_found} = Workspaces.fetch(account, "invalid")
    assert {:error, :invalid_request} = Workspaces.ensure(account, "invalid")
  end

  test "an old release cannot clear a replacement residency" do
    sandbox = Repo.insert!(%Sandbox{account_id: user_fixture().account.id, state: :running, residency_work_id: "new"})
    assert :ok = Sandboxes.end_residency(sandbox.id, "old")
    assert Repo.reload!(sandbox).residency_work_id == "new"
  end
end
