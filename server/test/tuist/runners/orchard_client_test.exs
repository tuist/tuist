defmodule Tuist.Runners.OrchardClientTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Runners.OrchardClient
  alias Tuist.Runners.OrchardConfig

  setup :verify_on_exit!

  @config %OrchardConfig{
    controller_url: "https://orchard.example.com",
    service_account_name: "test-sa",
    service_account_token: "test-token"
  }

  describe "create_vm/2" do
    test "creates a VM successfully" do
      expect(Req, :post, fn opts ->
        assert opts[:url] == "https://orchard.example.com/v1/vms"
        assert opts[:json]["name"] == "test-vm"
        assert opts[:json]["image"] == "ghcr.io/tuist/runner:latest"
        assert opts[:auth] == {:basic, "test-sa:test-token"}

        {:ok, %Req.Response{status: 201, body: %{"name" => "test-vm", "status" => "creating"}}}
      end)

      assert {:ok, %{"name" => "test-vm"}} =
               OrchardClient.create_vm(@config, %{
                 name: "test-vm",
                 image: "ghcr.io/tuist/runner:latest"
               })
    end

    test "returns error on API failure" do
      expect(Req, :post, fn _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "internal error"}}}
      end)

      assert {:error, _} =
               OrchardClient.create_vm(@config, %{
                 name: "test-vm",
                 image: "ghcr.io/tuist/runner:latest"
               })
    end
  end

  describe "delete_vm/2" do
    test "deletes a VM successfully" do
      expect(Req, :delete, fn opts ->
        assert opts[:url] == "https://orchard.example.com/v1/vms/test-vm"
        {:ok, %Req.Response{status: 204, body: ""}}
      end)

      assert :ok = OrchardClient.delete_vm(@config, "test-vm")
    end

    test "returns ok when VM not found" do
      expect(Req, :delete, fn _opts ->
        {:ok, %Req.Response{status: 404, body: %{"error" => "not found"}}}
      end)

      assert :ok = OrchardClient.delete_vm(@config, "nonexistent-vm")
    end
  end

  describe "get_vm/2" do
    test "gets VM details" do
      expect(Req, :get, fn opts ->
        assert opts[:url] == "https://orchard.example.com/v1/vms/test-vm"

        {:ok,
         %Req.Response{
           status: 200,
           body: %{"name" => "test-vm", "status" => "running", "ip" => "192.168.1.1"}
         }}
      end)

      assert {:ok, %{"name" => "test-vm", "status" => "running"}} =
               OrchardClient.get_vm(@config, "test-vm")
    end
  end
end
