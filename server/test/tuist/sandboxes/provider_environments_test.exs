defmodule Tuist.Sandboxes.ProviderEnvironmentsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.ProviderEnvironment
  alias Tuist.Sandboxes.ProviderEnvironments
  alias Tuist.Sandboxes.Sandbox

  setup do
    stub(FeatureFlags, :sandboxes_enabled?, fn _ -> true end)
    %{account: account_fixture(), key: Ecto.UUID.generate()}
  end

  test "delayed starts cannot undo a pause or deletion and another account cannot execute the mapping", c do
    stub(Sandboxes, :create_sandbox, fn account, attrs ->
      sandbox = %Sandbox{account_id: account.id, provider_environment_id: attrs.provider_environment_id, state: :running}
      {:ok, Repo.insert!(sandbox)}
    end)

    stub(Sandboxes, :pause, fn sandbox -> {:ok, sandbox |> Ecto.Changeset.change(state: :paused) |> Repo.update!()} end)
    stub(Sandboxes, :delete, fn sandbox -> Repo.delete(sandbox) end)

    stub(Sandboxes, :ensure_running, fn sandbox ->
      {:ok, sandbox |> Ecto.Changeset.change(state: :running) |> Repo.update!()}
    end)

    assert {:ok, %{state: "ready"}} = ProviderEnvironments.dispatch(c.account, c.key, :start, %{"generation" => 2})
    binding = Repo.get_by!(ProviderEnvironment, account_id: c.account.id, external_key: c.key)
    sandbox = Repo.get_by!(Sandbox, provider_environment_id: binding.id)
    assert {:ok, _} = ProviderEnvironments.dispatch(c.account, c.key, :pause, %{"generation" => 3})

    for generation <- [2, 3] do
      assert {:error, :stale_generation} =
               ProviderEnvironments.dispatch(c.account, c.key, :start, %{"generation" => generation})
    end

    assert Repo.reload!(sandbox).state == :paused
    assert {:ok, _} = ProviderEnvironments.dispatch(c.account, c.key, :start, %{"generation" => 4})
    assert Repo.get_by!(Sandbox, provider_environment_id: binding.id).id == sandbox.id

    params = %{
      "generation" => 4,
      "id" => Ecto.UUID.generate(),
      "tool" => "environment_terminal",
      "arguments" => %{"project_id" => Ecto.UUID.generate(), "command" => "pwd"},
      "execution_timeout_seconds" => 600
    }

    stub(Sandboxes, :exec, fn actual, argv, opts ->
      assert actual.id == sandbox.id
      assert argv == ["/bin/sh", "-lc", "pwd"]
      assert opts[:cwd] == "/workspace"
      {:ok, %{exit_code: 0, stdout: "/workspace\n", stderr: ""}}
    end)

    assert {:ok, %{success: true, output: "/workspace\n"}} =
             ProviderEnvironments.dispatch(c.account, c.key, :exec, params)

    assert {:error, :unavailable} = ProviderEnvironments.dispatch(account_fixture(), c.key, :exec, params)

    assert {:error, :invalid_params} =
             ProviderEnvironments.dispatch(c.account, c.key, :exec, Map.put(params, "execution_timeout_seconds", 1800))

    assert {:ok, _} = ProviderEnvironments.dispatch(c.account, c.key, :delete, %{"generation" => 5})
    refute Repo.get(Sandbox, sandbox.id)
    assert {:error, :stale_generation} = ProviderEnvironments.dispatch(c.account, c.key, :start, %{"generation" => 5})
    assert Repo.reload!(binding).generation == 5
  end

  test "a stop arriving before start creates a tombstone, even when provisioning is disabled", c do
    stub(FeatureFlags, :sandboxes_enabled?, fn _ -> false end)
    assert {:ok, %{state: "paused"}} = ProviderEnvironments.dispatch(c.account, c.key, :pause, %{"generation" => 7})
    assert {:error, :disabled} = ProviderEnvironments.dispatch(c.account, c.key, :start, %{"generation" => 8})
    assert Repo.get_by!(ProviderEnvironment, account_id: c.account.id, external_key: c.key).generation == 7
  end
end
