defmodule Tuist.MCP.Components.Tools.AccountTokenToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.MCP.Components.Tools.GetAccountToken
  alias Tuist.MCP.Components.Tools.ListAccountTokens
  alias Tuist.MCP.Components.Tools.ListProjectTokens
  alias Tuist.Projects

  describe "list_account_tokens" do
    test "returns non-secret token metadata" do
      account = %{id: 1, name: "acme"}
      token = token_fixture()

      stub(Accounts, :get_account_by_handle, fn "acme" -> account end)
      stub(Tuist.Authorization, :authorize, fn :account_token_read, :subject, ^account -> :ok end)

      stub(Accounts, :list_account_tokens, fn ^account, _attrs ->
        {[token], pagination_metadata()}
      end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               ListAccountTokens.call(conn, %{"account_handle" => "acme"})

      assert %{
               "tokens" => [%{"id" => "token-1", "name" => "build-insights", "project_handles" => ["app"]}]
             } = JSON.decode!(text)
    end
  end

  describe "get_account_token" do
    test "returns one token without its secret" do
      account = %{id: 1, name: "acme"}
      token = token_fixture()

      stub(Accounts, :get_account_by_handle, fn "acme" -> account end)
      stub(Tuist.Authorization, :authorize, fn :account_token_read, :subject, ^account -> :ok end)
      stub(Accounts, :get_account_token, fn ^account, "token-1" -> {:ok, token} end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               GetAccountToken.call(conn, %{"account_handle" => "acme", "token_id" => "token-1"})

      assert JSON.decode!(text)["id"] == "token-1"
    end
  end

  describe "list_project_tokens" do
    test "returns project token metadata after account authorization" do
      account = %{id: 1, name: "acme"}
      project = %{id: 2, name: "app", account: account}
      project_token = %{id: "project-token-1", inserted_at: ~U[2026-01-01 12:00:00Z]}

      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)
      stub(Tuist.Authorization, :authorize, fn :account_token_read, :subject, ^account -> :ok end)
      stub(Projects, :get_project_tokens, fn ^project -> [project_token] end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               ListProjectTokens.call(conn, %{"account_handle" => "acme", "project_handle" => "app"})

      assert JSON.decode!(text) == %{
               "tokens" => [%{"id" => "project-token-1", "inserted_at" => "2026-01-01T12:00:00Z"}]
             }
    end
  end

  defp token_fixture do
    %{
      id: "token-1",
      name: "build-insights",
      scopes: ["project:builds:read"],
      all_projects: false,
      expires_at: nil,
      inserted_at: ~U[2026-01-01 12:00:00Z],
      projects: [%{name: "app"}]
    }
  end

  defp pagination_metadata do
    %{
      has_next_page?: false,
      has_previous_page?: false,
      total_count: 1,
      total_pages: 1,
      current_page: 1,
      page_size: 20
    }
  end
end
