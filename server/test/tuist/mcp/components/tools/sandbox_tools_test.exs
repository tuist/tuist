defmodule Tuist.MCP.Components.Tools.SandboxToolsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.FeatureFlags
  alias Tuist.MCP.Components.Tools.CreateSandbox
  alias Tuist.MCP.Components.Tools.DeleteSandbox
  alias Tuist.MCP.Components.Tools.GetSandbox
  alias Tuist.MCP.Components.Tools.GetSandboxAnalytics
  alias Tuist.MCP.Components.Tools.ListSandboxes
  alias Tuist.Repo
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    account = AccountsFixtures.account_fixture()
    stub(FeatureFlags, :sandboxes_enabled?, fn _account -> true end)
    %{account: account, conn: %Plug.Conn{assigns: %{current_subject: :subject}}}
  end

  test "read tools require account administration and return the shared contract", %{account: account, conn: conn} do
    sandbox = sandbox_fixture(account: account, state: :paused, paused_at: DateTime.utc_now())
    sandbox_fixture(state: :paused)
    expect(Tuist.Authorization, :authorize, 3, fn :account_update, :subject, %{id: id} when id == account.id -> :ok end)

    assert %{
             "structuredContent" => %{
               "sandboxes" => [%{"id" => id, "status" => "paused"}],
               "pagination_metadata" => %{"total_count" => 1}
             }
           } = ListSandboxes.call(conn, %{"account_handle" => account.name})

    assert id == sandbox.id

    assert %{"structuredContent" => %{"id" => ^id, "state" => "paused"}} =
             GetSandbox.call(conn, %{"account_handle" => account.name, "sandbox_id" => id})

    assert %{"structuredContent" => %{"bucket" => "day", "concurrency" => %{"limits" => %{"vcpus" => 32}}}} =
             GetSandboxAnalytics.call(conn, %{"account_handle" => account.name})
  end

  test "create boots a sandbox of either platform with that platform's defaults", %{account: account, conn: conn} do
    stub(Tuist.Authorization, :authorize, fn :account_update, :subject, _account -> :ok end)

    expect(Capacity, :place, 2, fn sandbox ->
      node = if sandbox.platform == :darwin, do: "mac-1", else: "linux-1"
      sandbox |> Ecto.Changeset.change(node_name: node) |> Repo.update!()
      {:ok, node}
    end)

    expect(Nodes, :call, 2, fn
      "mac-1", "create", args, _opts ->
        assert %{template: "macos", vcpus: 8, memory_mb: 24_576, workspace_gb: 20} = args
        {:ok, %{"template_tag" => "macos-tag"}}

      "linux-1", "create", args, _opts ->
        assert %{template: "default", vcpus: 2, memory_mb: 4096} = args
        {:ok, %{"template_tag" => "linux-tag"}}
    end)

    assert %{"structuredContent" => %{"platform" => "darwin", "state" => "running", "memory_mb" => 24_576}} =
             CreateSandbox.call(conn, %{
               "account_handle" => account.name,
               "platform" => "darwin",
               "vcpus" => 8,
               "memory_mb" => 24_576,
               "workspace_gb" => 20
             })

    assert %{"structuredContent" => %{"platform" => "linux", "vcpus" => 2}} =
             CreateSandbox.call(conn, %{"account_handle" => account.name})
  end

  test "create refuses a shape the platform does not offer", %{account: account, conn: conn} do
    stub(Tuist.Authorization, :authorize, fn :account_update, :subject, _account -> :ok end)
    reject(&Capacity.place/1)
    reject(&Nodes.call/4)

    assert %{"isError" => true, "content" => [%{"text" => text}]} =
             CreateSandbox.call(conn, %{
               "account_handle" => account.name,
               "platform" => "darwin",
               "vcpus" => 4,
               "memory_mb" => 8192
             })

    assert text =~ "8x24576"
    refute Repo.exists?(Sandbox)
  end

  test "refuses a user who cannot administer the account", %{account: account, conn: conn} do
    sandbox = sandbox_fixture(account: account)
    stub(Tuist.Authorization, :authorize, fn _action, _subject, _account -> {:error, :forbidden} end)
    reject(&Nodes.call/4)

    assert %{"isError" => true} =
             DeleteSandbox.call(conn, %{"account_handle" => account.name, "sandbox_id" => sandbox.id})

    assert Repo.get(Sandbox, sandbox.id)
  end

  test "does not reach another account's sandbox", %{account: account, conn: conn} do
    foreign = sandbox_fixture()
    stub(Tuist.Authorization, :authorize, fn :account_update, :subject, _account -> :ok end)
    reject(&Nodes.call/4)

    assert %{"isError" => true, "content" => [%{"text" => "Sandbox not found."}]} =
             DeleteSandbox.call(conn, %{"account_handle" => account.name, "sandbox_id" => foreign.id})

    assert Repo.get(Sandbox, foreign.id)
  end

  test "reports a disabled account", %{account: account, conn: conn} do
    stub(Tuist.Authorization, :authorize, fn :account_update, :subject, _account -> :ok end)
    stub(FeatureFlags, :sandboxes_enabled?, fn _account -> false end)

    assert %{"isError" => true, "content" => [%{"text" => text}]} =
             ListSandboxes.call(conn, %{"account_handle" => account.name})

    assert text =~ "not enabled"
  end
end
