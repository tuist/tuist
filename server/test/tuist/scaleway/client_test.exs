defmodule Tuist.Scaleway.ClientTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Scaleway
  alias Tuist.Scaleway.Client

  setup :verify_on_exit!

  @config %Scaleway{secret_key: "test-secret", project_id: "proj-123"}

  describe "create_server/2" do
    test "creates an apple silicon server" do
      expect(Req, :post, fn opts ->
        assert opts[:url] == "https://api.scaleway.com/apple-silicon/v1alpha1/zones/fr-par-3/servers"

        assert opts[:json] == %{
                 "name" => "worker-01",
                 "type" => "M1-M",
                 "os_id" => "os-uuid",
                 "project_id" => "proj-123"
               }

        assert {"X-Auth-Token", "test-secret"} in opts[:headers]

        {:ok,
         %Req.Response{
           status: 201,
           body: %{
             "id" => "server-uuid",
             "ip" => "1.2.3.4",
             "sudo_password" => "SeCrEt",
             "ssh_username" => "m1"
           }
         }}
      end)

      assert {:ok, %{"id" => "server-uuid"}} =
               Client.create_server(@config, %{
                 name: "worker-01",
                 zone: "fr-par-3",
                 server_type: "M1-M",
                 os_id: "os-uuid"
               })
    end
  end

  describe "delete_server/3" do
    test "returns :ok on 204" do
      expect(Req, :delete, fn _opts ->
        {:ok, %Req.Response{status: 204, body: ""}}
      end)

      assert :ok = Client.delete_server(@config, "fr-par-3", "server-uuid")
    end

    test "returns :ok when server is already gone" do
      expect(Req, :delete, fn _opts ->
        {:ok, %Req.Response{status: 404, body: ""}}
      end)

      assert :ok = Client.delete_server(@config, "fr-par-3", "server-uuid")
    end
  end

  describe "find_os_id/3" do
    test "returns the OS id matching the given name" do
      expect(Req, :get, fn opts ->
        assert opts[:url] == "https://api.scaleway.com/apple-silicon/v1alpha1/zones/fr-par-3/os"

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "os" => [
               %{"id" => "os-1", "name" => "macos-tahoe-26.0"},
               %{"id" => "os-2", "name" => "macos-sonoma-14.7"}
             ]
           }
         }}
      end)

      assert {:ok, "os-1"} = Client.find_os_id(@config, "fr-par-3", "macos-tahoe-26.0")
    end

    test "returns an error when the OS is not found" do
      expect(Req, :get, fn _opts ->
        {:ok, %Req.Response{status: 200, body: %{"os" => []}}}
      end)

      assert {:error, {:os_not_found, "macos-tahoe-26.0"}} =
               Client.find_os_id(@config, "fr-par-3", "macos-tahoe-26.0")
    end
  end
end
