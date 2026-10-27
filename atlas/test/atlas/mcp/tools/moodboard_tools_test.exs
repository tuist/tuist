defmodule Atlas.MCP.Tools.MoodboardToolsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.LLMs.Runner
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.AddMoodboardComment
  alias Atlas.MCP.Tools.CreateMoodboardResource
  alias Atlas.MCP.Tools.DeleteMoodboardComment
  alias Atlas.MCP.Tools.DeleteMoodboardResource
  alias Atlas.MCP.Tools.GetMoodboardResource
  alias Atlas.MCP.Tools.ListMoodboardResources
  alias Atlas.MCP.Tools.SearchMoodboardResources
  alias Atlas.MCP.Tools.SuggestMoodboardResource
  alias Atlas.MCP.Tools.UpdateMoodboardResource
  alias Atlas.Moodboard.Resource

  @tools [
    CreateMoodboardResource,
    SuggestMoodboardResource,
    ListMoodboardResources,
    UpdateMoodboardResource,
    DeleteMoodboardResource,
    GetMoodboardResource,
    SearchMoodboardResources,
    AddMoodboardComment,
    DeleteMoodboardComment
  ]

  test "creates, browses, edits and removes resources with valid output contracts" do
    user = insert_user!()
    conn = mcp_conn(user)

    assert {:ok, %{resource: resource}} =
             execute_tool(CreateMoodboardResource, conn, %{
               "title" => "Interface inspiration",
               "url" => "https://design.example/#{System.unique_integer([:positive])}",
               "tags" => ["interfaces"]
             })

    assert resource.created_by_id == user.id

    assert {:ok, %{resources: [%{id: id}], has_more: false, next_offset: nil}} =
             execute_tool(ListMoodboardResources, conn, %{"query" => "Interface", "tag" => "interfaces"})

    assert id == resource.id

    assert {:ok, %{resource: %{title: "Revised"}}} =
             execute_tool(UpdateMoodboardResource, conn, %{"resource_id" => id, "title" => "Revised"})

    assert {:ok, %{deleted: true}} = execute_tool(DeleteMoodboardResource, conn, %{"resource_id" => id})
  end

  test "suggestions and replay-safe saves share the native capture contract" do
    Mimic.stub(Runner, :fetch_config, fn -> {:error, :llm_not_configured} end)
    conn = mcp_conn(insert_user!())

    assert {:ok, %{suggestions: %{title: "Original text", generated: false}}} =
             execute_tool(SuggestMoodboardResource, conn, %{"content" => "Original text"})

    fields = %{"request_id" => Ecto.UUID.generate(), "title" => "Reviewed", "content" => "Original text"}
    assert {:ok, %{resource: resource}} = execute_tool(CreateMoodboardResource, conn, fields)
    assert {:ok, %{resource: replayed}} = execute_tool(CreateMoodboardResource, conn, fields)
    assert replayed.id == resource.id
  end

  test "text entries, conversations and content search satisfy their output contracts" do
    conn = mcp_conn(insert_user!())
    other_conn = mcp_conn(insert_user!())

    assert {:ok, %{resource: resource}} =
             execute_tool(CreateMoodboardResource, conn, %{
               "title" => "A principle",
               "content" => "Make the important thing obvious",
               "description" => "Our review note"
             })

    assert resource.url == nil
    assert resource.kind == "text"

    assert {:ok, %{comment: comment}} =
             execute_tool(AddMoodboardComment, other_conn, %{
               "resource_id" => resource.id,
               "body" => "Choreography matters here"
             })

    assert {:ok, %{resource: %{id: id}, comments: [%{id: comment_id}], next_offset: nil}} =
             execute_tool(GetMoodboardResource, conn, %{"resource_id" => resource.id})

    assert id == resource.id
    assert comment_id == comment.id
    Mimic.stub(Atlas.Vector, :configured?, fn -> false end)

    assert {:ok, %{resources: [%{id: ^id}]}} =
             execute_tool(SearchMoodboardResources, conn, %{"query" => "Choreography"})

    assert {:error, _message} = execute_tool(DeleteMoodboardComment, conn, %{"comment_id" => comment.id})
    assert {:ok, %{deleted: true}} = execute_tool(DeleteMoodboardComment, other_conn, %{"comment_id" => comment.id})
    assert {:ok, %{comments: []}} = execute_tool(GetMoodboardResource, conn, %{"resource_id" => resource.id})
  end

  test "pagination exposes the next offset and can traverse the collection" do
    conn = mcp_conn(insert_user!())

    for index <- 1..3 do
      assert {:ok, _response} =
               execute_tool(CreateMoodboardResource, conn, %{
                 "title" => "Reference #{index}",
                 "url" => "https://design.example/#{System.unique_integer([:positive])}"
               })
    end

    assert {:ok, %{resources: first_page, has_more: true, next_offset: 2}} =
             execute_tool(ListMoodboardResources, conn, %{"page_size" => 2})

    assert {:ok, %{resources: second_page, has_more: false, next_offset: nil}} =
             execute_tool(ListMoodboardResources, conn, %{"page_size" => 2, "offset" => 2})

    assert length(Enum.uniq_by(first_page ++ second_page, & &1.id)) == 3
  end

  test "list and search use the same literal and discussion query semantics" do
    user = insert_user!()
    conn = mcp_conn(user)

    {:ok, resource} =
      Atlas.Moodboard.create_resource(
        %{title: "A design reference", url: "https://radix-ui.com/primitives", tags: ["typography"]},
        user
      )

    {:ok, _} = Atlas.Moodboard.add_comment(resource.id, %{body: "Discuss choreography"}, user)

    {:ok, :ok} =
      Atlas.Moodboard.apply_preview(
        resource.id,
        resource.preview_revision,
        {:ok, %{source_text: "Extracted article body"}}
      )

    Mimic.stub(Atlas.Vector, :configured?, fn -> false end)

    for query <- ["radix-ui.com", "radix", "typo", "choreo", "Extracted"] do
      assert {:ok, %{resources: listed}} = execute_tool(ListMoodboardResources, conn, %{"query" => query})
      assert {:ok, %{resources: searched}} = execute_tool(SearchMoodboardResources, conn, %{"query" => query})
      assert Enum.map(listed, & &1.id) == [resource.id]
      assert Enum.map(searched, & &1.id) == [resource.id]
    end
  end

  test "a maximum list page returns bounded untrusted summaries while get retains full text" do
    user = insert_user!()
    conn = mcp_conn(user)
    long = String.duplicate("x", 20_000)

    for index <- 1..100 do
      {:ok, _} = Atlas.Moodboard.create_resource(%{title: "Reference #{index}", content: long}, user)
    end

    Atlas.Repo.update_all(Resource, set: [source_text: long])
    assert {:ok, %{resources: resources} = response} = execute_tool(ListMoodboardResources, conn, %{"page_size" => 100})
    assert length(resources) == 100
    assert byte_size(Jason.encode!(response)) < 200_000

    for resource <- resources do
      refute Map.has_key?(resource, :content)
      refute Map.has_key?(resource, :source_text)
      assert resource.has_full_text
      assert String.length(resource.excerpt) == 280
    end

    assert {:ok, %{resource: full}} = execute_tool(GetMoodboardResource, conn, %{"resource_id" => hd(resources).id})
    assert full.content == long
    assert full.source_text == long
  end

  test "requires authentication even for direct execution" do
    for tool <- @tools do
      assert {:error, message} = execute_tool(tool, mcp_conn(nil), %{})
      assert message =~ "authenticated"
    end
  end

  test "another teammate cannot change a contribution" do
    conn = mcp_conn(insert_user!())
    other_conn = mcp_conn(insert_user!())

    {:ok, %{resource: resource}} =
      execute_tool(CreateMoodboardResource, conn, %{
        "title" => "A reference",
        "url" => "https://design.example/#{System.unique_integer([:positive])}"
      })

    for tool <- [UpdateMoodboardResource, DeleteMoodboardResource] do
      assert {:error, message} = execute_tool(tool, other_conn, %{"resource_id" => resource.id})
      assert message =~ "Only the contributor"
    end

    assert {:error, "Resource not found."} = execute_tool(DeleteMoodboardResource, conn, %{"resource_id" => "bad"})
  end

  test "tools are discovered in the default group, including restricted sessions" do
    conn = mcp_conn(insert_user!())
    restricted = put_in(conn, [:assigns, :mcp_claims], %{"mcp_tool_groups" => ["finance"]})

    Mimic.stub(Proxy, :list_hoisted_tools, fn _conn -> [] end)
    request = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}
    visible = Server.handle_message(conn, request)["result"]["tools"]
    restricted_tools = Server.handle_message(restricted, request)["result"]["tools"]

    for tool <- @tools do
      assert Enum.any?(visible, &(&1["name"] == tool.name()))
      assert Enum.any?(restricted_tools, &(&1["name"] == tool.name()))
    end
  end
end
