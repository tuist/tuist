defmodule Atlas.GTM.Outreach.BraveSearchTest do
  use ExUnit.Case, async: true

  alias Atlas.GTM.Outreach.BraveSearch

  test "maps Brave web results into GTM signal attributes" do
    parent = self()

    request = fn opts ->
      send(parent, {:brave_request, opts})

      assert opts[:url] == "https://api.search.brave.com/res/v1/web/search"
      assert {"X-Subscription-Token", "brave-key"} in opts[:headers]
      assert opts[:params] == [q: ~s("Tuist" "engineering blog"), count: 2]

      {:ok,
       %{
         status: 200,
         body: %{
           "web" => %{
             "results" => [
               %{
                 "url" => "https://www.acme.example/blog/tuist-xcode-ci",
                 "title" => "Acme improves Xcode CI with Tuist",
                 "description" =>
                   "The mobile platform engineering team talks about Swift modules and developer productivity.",
                 "profile" => %{"url" => "acme.example/blog/tuist-xcode-ci"}
               },
               %{"title" => "Missing URL"}
             ]
           }
         }
       }}
    end

    assert {:ok, [signal]} =
             BraveSearch.search(~s("Tuist" "engineering blog"), api_key: "brave-key", request: request, count: 2)

    assert_receive {:brave_request, _opts}

    assert signal.company_name == "Acme"
    assert signal.company_key == "domain:acme.example"
    assert signal.domain == "acme.example"
    assert signal.source == "brave"
    assert signal.source_ref == "https://www.acme.example/blog/tuist-xcode-ci"
    assert signal.signal_kind == "tuist_mention"
    assert signal.confidence == 90
    assert "Tuist" in signal.matched_terms
    assert "Xcode" in signal.matched_terms
    assert "Swift" in signal.matched_terms
    assert signal.metadata["display_url"] == "acme.example/blog/tuist-xcode-ci"
    assert signal.metadata["mention_type"] == "tuist_public_mention"
    assert signal.metadata["query"] == ~s("Tuist" "engineering blog")
    assert %DateTime{} = signal.observed_at
  end

  test "surfaces request errors and missing API key configuration" do
    assert {:error, :brave_search_api_key_not_configured} = BraveSearch.search("iOS CI")

    request = fn _opts -> {:ok, %{status: 429, body: %{"message" => "quota exceeded"}}} end

    assert {:error, message} = BraveSearch.search("iOS CI", api_key: "brave-key", request: request)
    assert message =~ "Brave Search request returned 429"
    assert message =~ "quota exceeded"
  end
end
