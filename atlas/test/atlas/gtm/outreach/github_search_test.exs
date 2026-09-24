defmodule Atlas.GTM.Outreach.GitHubSearchTest do
  use ExUnit.Case, async: true

  alias Atlas.GTM.Outreach.GitHubSearch

  test "enriches Tuist code search results with developer and company metadata" do
    get = fn _req, opts ->
      case opts[:url] do
        "/search/code" ->
          assert opts[:params][:q] == "Tuist filename:Project.swift"

          {:ok,
           %{
             status: 200,
             body: %{
               "items" => [
                 %{
                   "path" => "Project.swift",
                   "html_url" => "https://github.com/mobiledev/ios-app/blob/main/Project.swift",
                   "repository" => %{
                     "full_name" => "mobiledev/ios-app",
                     "html_url" => "https://github.com/mobiledev/ios-app",
                     "owner" => %{
                       "login" => "mobiledev",
                       "type" => "User",
                       "html_url" => "https://github.com/mobiledev"
                     }
                   }
                 }
               ]
             }
           }}

        "/users/mobiledev" ->
          {:ok,
           %{
             status: 200,
             body: %{
               "login" => "mobiledev",
               "name" => "Maya Singh",
               "company" => "@Acme Mobile",
               "html_url" => "https://github.com/mobiledev",
               "blog" => "https://acme.example"
             }
           }}
      end
    end

    assert {:ok, [signal]} = GitHubSearch.search("Tuist filename:Project.swift", req: Req.new(), get: get)

    assert signal.company_name == "Acme Mobile"
    assert signal.company_key == "github-company:acme-mobile"
    assert signal.signal_kind == "tuist_mention"
    assert "Project.swift" in signal.matched_terms
    assert "Tuist" in signal.matched_terms
    assert signal.metadata["mention_type"] == "tuist_public_mention"
    assert signal.metadata["owner_company"] == "Acme Mobile"
    assert signal.metadata["person"]["login"] == "mobiledev"
    assert signal.metadata["person"]["name"] == "Maya Singh"
    assert signal.metadata["person"]["company"] == "Acme Mobile"
    assert signal.metadata["person"]["title"] == "Public Tuist advocate"
  end
end
