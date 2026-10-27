defmodule Atlas.MCP.Tools.DisconnectLLMProviderTest do
  use Atlas.DataCase, async: true

  alias Atlas.LLMs.Connections
  alias Atlas.MCP.Tools.DisconnectLLMProvider
  alias Atlas.Users.User

  test "disconnects only the caller's provider even if another owner is supplied" do
    user = insert_user()
    other = insert_user()
    token = "sk-ant-oat01-" <> String.duplicate("a", 64)
    assert {:ok, _} = Connections.connect_claude(user, token)
    assert {:ok, _} = Connections.connect_claude(other, token)

    assert {:ok, %{disconnected: true}} =
             DisconnectLLMProvider.execute(%{assigns: %{current_user: user}}, %{
               "provider" => "claude",
               "user_id" => other.id
             })

    assert {:error, :not_connected} = Connections.credentials(user, "claude")
    assert {:ok, _} = Connections.credentials(other, "claude")
    assert {:error, _} = DisconnectLLMProvider.execute(%{assigns: %{}}, %{"provider" => "claude"})
  end

  defp insert_user do
    %User{}
    |> User.changeset(%{email: "llm-disconnect-#{System.unique_integer([:positive])}@tuist.dev"})
    |> Repo.insert!()
  end
end
