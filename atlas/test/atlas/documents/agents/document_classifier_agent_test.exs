defmodule Atlas.Documents.Agents.DocumentClassifierAgentTest do
  use Atlas.DataCase, async: true

  alias Atlas.Documents
  alias Atlas.Documents.Agents.DocumentClassifierAgent
  alias Atlas.Documents.Correspondent

  defp tool(name) do
    Enum.find(DocumentClassifierAgent.tools(), &(&1.name == name))
  end

  describe "tools/0" do
    test "exposes list and create tools for each normalized entity" do
      names = Enum.map(DocumentClassifierAgent.tools(), & &1.name)

      assert Enum.sort(names) == [
               "create_correspondent",
               "create_document_type",
               "create_tag",
               "list_correspondents",
               "list_document_types",
               "list_tags"
             ]
    end
  end

  describe "list tools" do
    test "list_correspondents returns the existing names" do
      Documents.upsert_correspondent("Acme")
      Documents.upsert_correspondent("Globex")

      assert {:ok, %{names: names}} = tool("list_correspondents").call.(%{}, %{})
      assert Enum.sort(names) == ["Acme", "Globex"]
    end
  end

  describe "create tools" do
    test "create_correspondent reuses a fuzzy match instead of duplicating" do
      existing = Documents.upsert_correspondent("Acme Inc.")

      assert {:ok, %{name: "Acme Inc."}} = tool("create_correspondent").call.(%{"name" => "Acme Inc"}, %{})
      assert Repo.aggregate(Correspondent, :count) == 1
      assert Documents.correspondents() |> hd() |> Map.get(:id) == existing.id
    end

    test "create_correspondent creates a new entry when nothing matches" do
      assert {:ok, %{name: "Initech"}} = tool("create_correspondent").call.(%{"name" => "Initech"}, %{})
      assert Repo.aggregate(Correspondent, :count) == 1
    end

    test "create_tag returns an error for a blank name" do
      assert {:error, _message} = tool("create_tag").call.(%{"name" => "   "}, %{})
    end
  end
end
