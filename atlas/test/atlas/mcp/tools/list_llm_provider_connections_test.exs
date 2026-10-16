defmodule Atlas.MCP.Tools.ListLLMProviderConnectionsTest do
  use Atlas.DataCase, async: true

  alias Atlas.LLMs.Connections
  alias Atlas.MCP.Tools.ListLLMProviderConnections
  alias Atlas.Users.User

  test "returns only caller-scoped metadata and requires authentication" do
    user = insert_user()
    other = insert_user()
    token = "sk-ant-oat01-" <> String.duplicate("a", 64)
    assert {:ok, _} = Connections.connect_claude(user, token)

    assert {:ok, %{providers: [%{provider: "claude", credential_configured: true}, _]}} =
             ListLLMProviderConnections.execute(%{assigns: %{current_user: user}}, %{})

    assert {:ok, %{providers: providers}} = ListLLMProviderConnections.execute(%{assigns: %{current_user: other}}, %{})
    assert Enum.all?(providers, &(!&1.credential_configured))
    refute JSON.encode!(providers) =~ token
    assert {:error, _} = ListLLMProviderConnections.execute(%{assigns: %{}}, %{})
  end

  defp insert_user do
    %User{} |> User.changeset(%{email: "llm-tool-#{System.unique_integer([:positive])}@tuist.dev"}) |> Repo.insert!()
  end
end
