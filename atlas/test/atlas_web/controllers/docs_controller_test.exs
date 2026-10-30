defmodule AtlasWeb.DocsControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Automations.Interfaces
  alias Atlas.Automations.Plan
  alias AtlasWeb.DocsHTML

  test "documentation is public and marked for the shared crawler rate limits", %{conn: conn} do
    for page <- DocsHTML.pages() do
      response = get(conn, "/docs/#{page.slug}")
      document = response |> html_response(200) |> LazyHTML.from_document()
      assert LazyHTML.query(document, "#docs-content") |> Enum.count() == 1
      assert LazyHTML.query(document, "#docs-sidebar [aria-current=page]") |> Enum.count() == 1
      assert get_resp_header(response, "x-tuist-public") == ["1"]
      assert get_resp_header(response, "x-robots-tag") == ["index, follow"]
      assert get_resp_header(response, "set-cookie") == []
    end
  end

  test "unfinished documentation is unavailable in both formats", %{conn: conn} do
    for slug <- ~w(installation first-administrator development configuration integrations workspace) do
      assert response(get(conn, "/docs/#{slug}"), 404)
      assert response(get(conn, "/docs-markdown/#{slug}"), 404)
    end
  end

  test "unknown documentation paths do not fall through to the application", %{conn: conn} do
    conn = get(conn, "/docs/missing/page")
    assert response(conn, 404)
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
  end

  test "anonymous application visits require login rather than redirecting to documentation", %{conn: conn} do
    assert redirected_to(get(conn, "/")) == "/login"
    assert redirected_to(get(conn, "/admin/users")) == "/login"
    assert get_resp_header(get(conn, "/admin/users"), "x-tuist-public") == []
  end

  test "every table of contents target exists in the rendered document", %{conn: conn} do
    for page <- DocsHTML.pages() do
      document = conn |> get("/docs/#{page.slug}") |> html_response(200) |> LazyHTML.from_document()

      for heading <- page.headings do
        assert LazyHTML.query(document, "h2##{heading.id}") |> Enum.count() == 1
      end
    end
  end

  test "documentation negotiates Markdown and varies cached responses by Accept", %{conn: conn} do
    for accept <- [
          "text/markdown",
          "text/markdown; charset=utf-8",
          "text/html;q=0.4, text/markdown;q=0.9",
          "text/html;q=0, */*;q=0.5, text/markdown;q=0.4"
        ] do
      response = conn |> put_req_header("accept", accept) |> get("/docs")
      assert response(response, 200) == DocsHTML.page("").markdown
      assert get_resp_header(response, "content-type") == ["text/markdown; charset=utf-8"]
      assert get_resp_header(response, "vary") == ["Accept"]
    end

    for accept <- ["text/html", "*/*", "text/html, text/markdown;q=0", "text/html;q=1, text/markdown;q=0.2"] do
      response = conn |> put_req_header("accept", accept) |> get("/docs")
      assert html_response(response, 200)
      assert get_resp_header(response, "vary") == ["Accept"]
    end
  end

  test "the plain-text page is the same source used by the copy action", %{conn: conn} do
    response = get(conn, "/docs-markdown")
    assert response(response, 200) == DocsHTML.page("").markdown
    assert get_resp_header(response, "content-type") == ["text/plain; charset=utf-8"]
    assert response(get(conn, "/docs-markdown/missing"), 404)
  end

  test "overview links to published guides and keeps page-copy controls", %{conn: conn} do
    document = conn |> get("/docs") |> html_response(200) |> LazyHTML.from_document()
    assert Enum.empty?(LazyHTML.query(document, "[data-part=hero-cards]"))
    assert Enum.count(LazyHTML.query(document, "#docs-nav-tabs")) == 1
    assert Enum.count(LazyHTML.query(document, "#docs-mobile-nav-tabs")) == 1
    assert Enum.count(LazyHTML.query(document, "#docs-sidebar [data-part=nav-link]")) == 5
    assert Enum.count(LazyHTML.query(document, "#docs-sidebar [data-part=nav-link][href='/docs/automation']")) == 1
    assert Enum.count(LazyHTML.query(document, "#docs-content a[href='/docs/automation']")) == 1
    assert Enum.count(LazyHTML.query(document, "#docs-sidebar [data-part=nav-link][href='/docs']")) == 1
    assert Enum.count(LazyHTML.query(document, "#docs-sidebar [data-part=nav-link][href='/docs/mcps']")) == 1
    assert Enum.count(LazyHTML.query(document, "#docs-sidebar [data-part=nav-link][href='/docs/ai-accounts']")) == 1
    assert Enum.empty?(LazyHTML.query(document, "#docs-sidebar [data-part=nav-link][href='/docs/ai-account-tools']"))
    assert Enum.count(LazyHTML.query(document, "#docs-content a[href='/docs/ai-accounts']")) == 1
    assert Enum.count(LazyHTML.query(document, "#docs-sidebar [data-part=nav-link][href='/docs/self-hosting']")) == 1
    assert Enum.count(LazyHTML.query(document, "[data-part=admonition][data-status=information]")) == 1
    assert Enum.count(LazyHTML.query(document, "#docs-copy-dropdown")) == 1
    assert Enum.count(LazyHTML.query(document, "#docs-mobile-copy-dropdown")) == 1
  end

  test "desktop and mobile category selectors match the page and isolate sidebar navigation", %{conn: conn} do
    for page <- DocsHTML.pages() do
      document = conn |> get("/docs/#{page.slug}") |> html_response(200) |> LazyHTML.from_document()
      sidebar = LazyHTML.query(document, "#docs-sidebar [data-part=nav-link]")
      expected = Enum.filter(DocsHTML.pages(), &(&1.category == page.category))
      assert Enum.count(sidebar) == length(expected)

      for id <- ["docs-nav-tabs", "docs-mobile-nav-tabs"] do
        assert Enum.count(LazyHTML.query(document, "##{id} a")) == 2

        assert Enum.count(LazyHTML.query(document, "##{id} [aria-current=true][data-category='#{page.category}']")) == 1

        assert Enum.count(LazyHTML.query(document, "##{id} a[href='/docs']")) == 1
        assert Enum.count(LazyHTML.query(document, "##{id} a[href='/docs/ai-account-tools']")) == 1
      end

      for item <- expected do
        path = if item.slug == "", do: "/docs", else: "/docs/#{item.slug}"
        link = LazyHTML.query(document, "#docs-sidebar [data-part=nav-link][href='#{path}']")
        assert Enum.count(link) == 1
        assert LazyHTML.text(link) |> String.trim() == item.sidebar_title
      end
    end
  end

  test "AI account setup is a standalone task-oriented guide", %{conn: conn} do
    document = conn |> get("/docs/ai-accounts") |> html_response(200) |> LazyHTML.from_document()
    content = document |> LazyHTML.query("#docs-content") |> LazyHTML.text()
    assert content =~ "Connect Claude or ChatGPT"
    assert content =~ "AI accounts"
    assert content =~ "Connect account"
    assert content =~ "claude setup-token"
    assert content =~ "sessions you start will use your connected account for inference"
    assert content =~ "use your connected ChatGPT account first, then Claude"
    assert content =~ "including a fallback after an unsuccessful attempt"
    assert content =~ "Other people's credentials are never used for your messages"

    assert document
           |> LazyHTML.query("#docs-sidebar [data-part=nav-link][href='/docs/ai-accounts']")
           |> LazyHTML.text()
           |> String.trim() == "AI accounts"

    assert content =~ "Update credentials"
    assert content =~ "Disconnect"
    refute content =~ "ATLAS_CHATGPT_CLIENT_ID"
    refute content =~ "connect_claude_provider"
    assert DocsHTML.page("ai-accounts").category == "Guides"
    assert Enum.count(LazyHTML.query(document, "h2#connect-claude")) == 1
    assert Enum.count(LazyHTML.query(document, "h2#connect-chatgpt")) == 1

    assert Enum.count(LazyHTML.query(document, "#docs-content a[href='/docs/self-hosting#enable-chatgpt-sign-in']")) ==
             1

    assert response(get(conn, "/docs-markdown/ai-accounts"), 200) == DocsHTML.page("ai-accounts").markdown
  end

  test "AI accounts has a domain reference under MCP with authorization and privacy guidance", %{conn: conn} do
    document = conn |> get("/docs/ai-account-tools") |> html_response(200) |> LazyHTML.from_document()
    text = document |> LazyHTML.query("#docs-content") |> LazyHTML.text()
    assert document |> LazyHTML.query("#docs-content h1") |> LazyHTML.text() == "AI accounts"

    assert document
           |> LazyHTML.query("#docs-sidebar [data-part=content-divider]")
           |> LazyHTML.text()
           |> String.trim() == "MCP"

    assert document
           |> LazyHTML.query("#docs-sidebar [data-part=nav-link][href='/docs/ai-account-tools']")
           |> LazyHTML.text()
           |> String.trim() == "AI accounts"

    for name <-
          ~w(list_llm_provider_connections connect_claude_provider start_chatgpt_provider_login poll_chatgpt_provider_login cancel_chatgpt_provider_login disconnect_llm_provider) do
      assert text =~ name
    end

    assert text =~ "potentially its model or conversation history"
    assert text =~ "cannot change installation-wide authorization-client configuration"
    assert text =~ "wait at least"
    assert DocsHTML.page("ai-account-tools").category == "References"
    assert DocsHTML.page("ai-account-tools").section == "MCP"
    assert response(get(conn, "/docs-markdown/ai-account-tools"), 200) == DocsHTML.page("ai-account-tools").markdown
  end

  test "Automation guide includes a valid plan with the documented task output references", %{conn: conn} do
    page = DocsHTML.page("automation")
    [_, source] = Regex.run(~r/```json\n(.*?)\n```/s, page.markdown)
    plan = JSON.decode!(source)
    assert {:ok, %{"steps" => [create, record]}} = Plan.compile(plan)
    assert create["behavior"]["type"] == "tasks.create"
    assert create["behavior"]["version"] == 2

    assert {:ok, %{"title" => "Prepare documents"}} =
             Plan.resolve(create["inputs"], %{"title" => "Prepare documents"}, %{})

    outputs = %{"create_task" => %{"task" => %{"id" => "created-task", "title" => "Prepare documents"}}}

    assert {:ok, %{"task_id" => "created-task", "title" => "Prepare documents"}} =
             Plan.resolve(record["inputs"], %{}, outputs)

    document = conn |> get("/docs/automation") |> html_response(200) |> LazyHTML.from_document()
    text = document |> LazyHTML.query("#docs-content") |> LazyHTML.text()
    assert text =~ "Build and run workflows"
    assert text =~ "Background push delivery and Live Activities are not implemented"
    assert text =~ "including a local macOS server"
    assert text =~ "automation:write"
    assert text =~ "Browse → Automation"
    assert page.category == "Guides"
    assert page.sidebar_title == "Automation"
    assert response(get(conn, "/docs-markdown/automation"), 200) == page.markdown
  end

  test "Automation reference covers every shared interface operation", %{conn: conn} do
    page = DocsHTML.page("automation-tools")
    document = conn |> get("/docs/automation-tools") |> html_response(200) |> LazyHTML.from_document()
    text = document |> LazyHTML.query("#docs-content") |> LazyHTML.text()

    for operation <- Interfaces.operations(), do: assert(text =~ operation.mcp)

    assert page.category == "References"
    assert page.section == "MCP"
    assert text =~ "request_id"
    assert text =~ "revision_id"
    assert text =~ "Cache-Control: no-store"
    assert response(get(conn, "/docs-markdown/automation-tools"), 200) == page.markdown
  end

  test "ChatGPT operator setup belongs to self-hosting, not the upstream MCP guide", %{conn: conn} do
    document = conn |> get("/docs/self-hosting") |> html_response(200) |> LazyHTML.from_document()
    assert Enum.count(LazyHTML.query(document, "h2#enable-chatgpt-sign-in")) == 1
    text = document |> LazyHTML.query("#docs-content") |> LazyHTML.text()
    assert text =~ "ATLAS_CHATGPT_CLIENT_ID"
    assert text =~ "Do not reuse Codex's or another application's client ID"
    assert text =~ "appSecretName"

    document = conn |> get("/docs/mcps") |> html_response(200) |> LazyHTML.from_document()
    text = document |> LazyHTML.query("#docs-content") |> LazyHTML.text()
    assert text =~ "upstream"
    refute text =~ "connect_claude_provider"
    refute text =~ "ATLAS_CHATGPT_CLIENT_ID"
    refute text =~ "Personal AI providers"
    refute response(get(conn, "/docs-markdown/mcps"), 200) =~ "## Personal AI providers"
  end

  test "trailing slashes share the overview canonical address", %{conn: conn} do
    document = conn |> get("/docs/") |> html_response(200) |> LazyHTML.from_document()
    assert Enum.count(LazyHTML.query(document, "link[rel=canonical][href$='/docs']")) == 1
    assert Enum.count(LazyHTML.query(document, "meta[property='og:url'][content$='/docs']")) == 1
  end

  test "every page advertises a page-specific social preview", %{conn: conn} do
    for page <- DocsHTML.pages() do
      document = conn |> get("/docs/#{page.slug}") |> html_response(200) |> LazyHTML.from_document()
      name = if(page.slug == "", do: "overview", else: page.slug)
      assert Enum.count(LazyHTML.query(document, "meta[property='og:image'][content$='/#{name}.png']")) == 1
      assert Enum.count(LazyHTML.query(document, "meta[name='twitter:card'][content='summary_large_image']")) == 1
    end
  end
end
