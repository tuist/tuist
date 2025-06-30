defmodule Tuist.OAuthTest do
  use TuistTestSupport.Cases.DataCase

  alias Boruta.Ecto.Client
  alias Tuist.OAuth

  describe "create_client/0" do
    test "creates an OAuth client with correct configuration" do
      assert {:ok, %Client{} = client} = OAuth.create_client()

      assert client.name == "Tuist"
    end
  end
end
