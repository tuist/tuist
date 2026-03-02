defmodule Tuist.OAuth.ClientsTest do
  use TuistTestSupport.Cases.DataCase

  alias Boruta.Oauth.Client
  alias Tuist.OAuth.Clients

  describe "create_client/1" do
    test "creates and fetches a dynamically registered client" do
      assert {:ok, %Client{id: client_id} = created_client} =
               Clients.create_client(%{
                 redirect_uris: ["http://localhost:3000/callback"],
                 name: "mcp-test-client"
               })

      assert %Client{id: ^client_id} = Clients.get_client(client_id)
      assert created_client.redirect_uris == ["http://localhost:3000/callback"]
      assert created_client.name == "mcp-test-client"
    end
  end
end
