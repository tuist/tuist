defmodule Tuist.MCP.Components.Tools.SandboxToolsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.FeatureFlags
  alias Tuist.MCP.Components.Tools.ArchiveSandbox
  alias Tuist.MCP.Components.Tools.BootSandboxDevice
  alias Tuist.MCP.Components.Tools.CreateSandbox
  alias Tuist.MCP.Components.Tools.DeleteSandbox
  alias Tuist.MCP.Components.Tools.GetSandbox
  alias Tuist.MCP.Components.Tools.GetSandboxAnalytics
  alias Tuist.MCP.Components.Tools.GetSandboxScreenshot
  alias Tuist.MCP.Components.Tools.LaunchSandboxApp
  alias Tuist.MCP.Components.Tools.ListSandboxDevices
  alias Tuist.MCP.Components.Tools.ListSandboxes
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    account = AccountsFixtures.account_fixture()
    stub(FeatureFlags, :sandboxes_enabled?, fn _account -> true end)
    %{account: account, conn: %Plug.Conn{assigns: %{current_subject: :subject}}}
  end

  test "read tools return the shared contract", %{account: account, conn: conn} do
    sandbox = sandbox_fixture(account: account, state: :paused, paused_at: DateTime.utc_now())
    sandbox_fixture(state: :paused)
    stub(Tuist.Authorization, :authorize, fn _action, :subject, %{id: id} when id == account.id -> :ok end)

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

  describe "an account member who isn't an administrator" do
    setup do
      admin = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: admin, preload: [:account])
      member = AccountsFixtures.user_fixture()
      :ok = Tuist.Accounts.add_user_to_organization(member, organization, role: :user)
      viewer = AccountsFixtures.user_fixture()
      :ok = Tuist.Accounts.add_user_to_organization(viewer, organization, role: :viewer)

      %{
        account: organization.account,
        conn: %Plug.Conn{assigns: %{current_user: member}},
        viewer_conn: %Plug.Conn{assigns: %{current_user: viewer}}
      }
    end

    test "lists, gets and deletes sandboxes", %{account: account, conn: conn} do
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      id = sandbox.id

      assert %{"structuredContent" => %{"sandboxes" => [%{"id" => ^id}]}} =
               ListSandboxes.call(conn, %{"account_handle" => account.name})

      assert %{"structuredContent" => %{"id" => ^id}} =
               GetSandbox.call(conn, %{"account_handle" => account.name, "sandbox_id" => id})

      expect(Nodes, :call, fn "node-a", "delete", _args, _opts -> {:ok, %{}} end)

      assert %{"structuredContent" => %{"id" => ^id, "deleted" => true}} =
               DeleteSandbox.call(conn, %{"account_handle" => account.name, "sandbox_id" => id})
    end

    test "reaches an agent's sandbox, analytics and archiving", %{account: account, conn: conn} do
      environment = agent_environment_fixture(account: account)

      sandbox =
        sandbox_fixture(
          account: account,
          state: :paused,
          paused_at: DateTime.utc_now(),
          agent_environment_id: environment.id
        )

      id = sandbox.id
      reject(&Nodes.call/4)

      assert %{"structuredContent" => %{"id" => ^id}} =
               GetSandbox.call(conn, %{"account_handle" => account.name, "sandbox_id" => id})

      assert %{"structuredContent" => %{"id" => ^id, "state" => "paused"}} =
               ArchiveSandbox.call(conn, %{"account_handle" => account.name, "sandbox_id" => id})

      assert %{"structuredContent" => %{"bucket" => "day"}} =
               GetSandboxAnalytics.call(conn, %{"account_handle" => account.name})
    end

    test "a viewer can't use sandboxes", %{account: account, viewer_conn: conn} do
      sandbox_fixture(account: account)

      assert %{"isError" => true, "content" => [%{"text" => text}]} =
               ListSandboxes.call(conn, %{"account_handle" => account.name})

      assert text =~ "do not have access"
    end
  end

  test "create boots a sandbox of either platform with that platform's defaults", %{account: account, conn: conn} do
    stub(Tuist.Authorization, :authorize, fn _action, :subject, _account -> :ok end)

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
        # A Linux sandbox bursts to 16 vCPUs and is guaranteed a quarter per GiB.
        assert %{template: "default", vcpus: 16, memory_mb: 4096, cpu_guarantee_milli: 1000} = args
        {:ok, %{"template_tag" => "linux-tag"}}
    end)

    assert %{
             "structuredContent" => %{
               "platform" => "darwin",
               "state" => "running",
               "memory_mb" => 24_576,
               "lifetime_seconds" => 600,
               "expires_at" => mac_expires_at
             }
           } =
             CreateSandbox.call(conn, %{
               "account_handle" => account.name,
               "platform" => "darwin",
               "vcpus" => 8,
               "memory_mb" => 24_576,
               "workspace_gb" => 20,
               "lifetime_seconds" => 600
             })

    assert_in_delta seconds_from_now(mac_expires_at), 600, 5

    # Without one, a sandbox gets the default two hours.
    assert %{
             "structuredContent" => %{
               "platform" => "linux",
               "vcpus" => 16,
               "guaranteed_vcpus" => 1,
               "lifetime_seconds" => 7200,
               "expires_at" => expires_at
             }
           } =
             CreateSandbox.call(conn, %{"account_handle" => account.name})

    assert_in_delta seconds_from_now(expires_at), 7200, 5
  end

  defp seconds_from_now(iso) do
    {:ok, at, 0} = DateTime.from_iso8601(iso)
    DateTime.diff(at, DateTime.utc_now())
  end

  test "create refuses a shape the platform does not offer", %{account: account, conn: conn} do
    stub(Tuist.Authorization, :authorize, fn _action, :subject, _account -> :ok end)
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

  test "refuses a user who cannot use the account's sandboxes", %{account: account, conn: conn} do
    sandbox = sandbox_fixture(account: account)
    stub(Tuist.Authorization, :authorize, fn _action, _subject, _account -> {:error, :forbidden} end)
    reject(&Nodes.call/4)

    assert %{"isError" => true} =
             DeleteSandbox.call(conn, %{"account_handle" => account.name, "sandbox_id" => sandbox.id})

    assert Repo.get(Sandbox, sandbox.id)
  end

  test "does not reach another account's sandbox", %{account: account, conn: conn} do
    foreign = sandbox_fixture()
    stub(Tuist.Authorization, :authorize, fn _action, :subject, _account -> :ok end)
    reject(&Nodes.call/4)

    assert %{"isError" => true, "content" => [%{"text" => "code: not_found\nSandbox not found."}]} =
             DeleteSandbox.call(conn, %{"account_handle" => account.name, "sandbox_id" => foreign.id})

    assert Repo.get(Sandbox, foreign.id)
  end

  test "reports a disabled account", %{account: account, conn: conn} do
    stub(Tuist.Authorization, :authorize, fn _action, :subject, _account -> :ok end)
    stub(FeatureFlags, :sandboxes_enabled?, fn _account -> false end)

    assert %{"isError" => true, "content" => [%{"text" => text}]} =
             ListSandboxes.call(conn, %{"account_handle" => account.name})

    assert text =~ "not enabled"
  end

  describe "simulator tools" do
    setup %{account: account} do
      stub(Tuist.Authorization, :authorize, fn _action, :subject, _account -> :ok end)
      sandbox = sandbox_fixture(account: account, platform: :darwin, template: "macos")
      %{args: %{"account_handle" => account.name, "sandbox_id" => sandbox.id}, sandbox_id: sandbox.id}
    end

    test "a screenshot comes back as an image with its size", %{conn: conn, args: args, sandbox_id: id} do
      jpeg = Base.encode64(<<0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3>>)

      expect(Sandboxes, :exec, fn %Sandbox{id: ^id}, ["/bin/bash", "-c", script], opts ->
        assert script == Tuist.Sandboxes.Devices.screenshot_script()
        assert opts[:env] == %{"TUIST_TARGET" => "device", "TUIST_DEVICE" => "iPhone 18 Pro"}

        {:ok,
         %{
           exit_code: 0,
           stdout: "1206 2622\n" <> String.slice(jpeg, 0, 4) <> "\n" <> String.slice(jpeg, 4..-1//1),
           stderr: ""
         }}
      end)

      assert %{
               "content" => [%{"type" => "image", "mimeType" => "image/jpeg", "data" => ^jpeg}, %{"type" => "text"}],
               "structuredContent" => %{
                 "target" => "device",
                 "device" => "iPhone 18 Pro",
                 "width" => 1206,
                 "height" => 2622,
                 "mime_type" => "image/jpeg"
               }
             } = GetSandboxScreenshot.call(conn, Map.put(args, "device", "iPhone 18 Pro"))
    end

    test "failures the agent can act on have their own codes", %{conn: conn, args: args} do
      stub(Sandboxes, :exec, fn _sandbox, _cmd, opts ->
        exit_code = if opts[:env]["TUIST_TARGET"] == "screen", do: 3, else: 4
        {:ok, %{exit_code: exit_code, stdout: "", stderr: ""}}
      end)

      assert %{"isError" => true, "content" => [%{"text" => "code: device_not_booted\nNo device is booted" <> _}]} =
               GetSandboxScreenshot.call(conn, args)

      assert %{"isError" => true, "content" => [%{"text" => "code: devices_unsupported\n" <> _}]} =
               GetSandboxScreenshot.call(conn, Map.put(args, "target", "screen"))

      stub(Sandboxes, :exec, fn _sandbox, _cmd, _opts -> {:ok, %{exit_code: 5, stdout: "", stderr: ""}} end)

      assert %{"isError" => true, "content" => [%{"text" => "code: device_not_found\n" <> text}]} =
               BootSandboxDevice.call(conn, Map.put(args, "device", "iPhone 1"))

      assert text =~ "iPhone 1"
    end

    test "a Linux sandbox answers devices_unsupported without running anything", %{conn: conn, account: account} do
      linux = sandbox_fixture(account: account, platform: :linux)
      reject(Sandboxes, :exec, 3)

      assert %{"isError" => true, "content" => [%{"text" => "code: devices_unsupported\n" <> _}]} =
               ListSandboxDevices.call(conn, %{"account_handle" => account.name, "sandbox_id" => linux.id})
    end

    test "only admins reach the devices of a sandbox that serves an integration", %{conn: conn, account: account} do
      stub(Tuist.Authorization, :authorize, fn
        :account_update, _subject, _account -> {:error, :forbidden}
        _action, _subject, _account -> :ok
      end)

      orb = sandbox_fixture(account: account, platform: :darwin, template: "macos", amp_orb_id: "orb-1")
      reject(Sandboxes, :exec, 3)

      assert %{"isError" => true, "content" => [%{"text" => "code: forbidden\n" <> _}]} =
               GetSandboxScreenshot.call(conn, %{"account_handle" => account.name, "sandbox_id" => orb.id})
    end

    test "lists the devices simctl reports and launches a built app", %{conn: conn, args: args} do
      devices = %{
        "devices" => %{
          "com.apple.CoreSimulator.SimRuntime.iOS-27-2" => [
            %{"name" => "iPhone 18 Pro", "udid" => "B0A2F104", "state" => "Booted", "isAvailable" => true}
          ]
        }
      }

      expect(Sandboxes, :exec, fn _sandbox, _cmd, _opts ->
        {:ok, %{exit_code: 0, stdout: JSON.encode!(devices), stderr: ""}}
      end)

      assert %{
               "structuredContent" => %{
                 "devices" => [
                   %{
                     "id" => "B0A2F104",
                     "name" => "iPhone 18 Pro",
                     "platform" => "ios",
                     "runtime" => "iOS 27.2",
                     "state" => "Booted"
                   }
                 ]
               }
             } = ListSandboxDevices.call(conn, args)

      # The path reaches the fixed script only as an environment variable.
      app_path = "build/dd/Build/Products/Debug-iphonesimulator/App.app; rm -rf ~"

      expect(Sandboxes, :exec, fn _sandbox, ["/bin/bash", "-c", script], opts ->
        refute script =~ "rm -rf"
        assert opts[:env] == %{"TUIST_DEVICE" => "booted", "TUIST_APP_ID" => "", "TUIST_APP_PATH" => app_path}
        {:ok, %{exit_code: 0, stdout: "dev.tuist.App", stderr: ""}}
      end)

      assert %{"structuredContent" => %{"app_id" => "dev.tuist.App", "device" => "booted"}} =
               LaunchSandboxApp.call(conn, Map.put(args, "app_path", app_path))
    end
  end
end
