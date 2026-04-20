defmodule Tuist.Scaleway.StubTest do
  use ExUnit.Case, async: true

  alias Tuist.Scaleway
  alias Tuist.Scaleway.Stub

  @config %Scaleway{secret_key: "stub", project_id: "stub"}

  test "create_server returns a stubbed server record" do
    assert {:ok, server} =
             Stub.create_server(@config, %{
               name: "test",
               zone: "fr-par-3",
               server_type: "M1-M",
               os_id: "stub-os-id"
             })

    assert server["id"] =~ ~r/^stub-/
    assert server["ip"] == "127.0.0.1"
    assert server["ssh_username"] == "stub"
  end

  test "delete_server is a no-op" do
    assert :ok = Stub.delete_server(@config, "fr-par-3", "stub-id")
  end

  test "find_os_id returns a stub id" do
    assert {:ok, "stub-os-id"} = Stub.find_os_id(@config, "fr-par-3", "anything")
  end

  test "Scaleway.config returns stub values when the stub client is wired" do
    original = Application.get_env(:tuist, :scaleway_client)
    Application.put_env(:tuist, :scaleway_client, Stub)

    on_exit(fn -> Application.put_env(:tuist, :scaleway_client, original) end)

    assert {:ok, %Scaleway{secret_key: "stub", project_id: "stub"}} = Scaleway.config()
  end
end
