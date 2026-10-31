defmodule Tuist.Runners.Bitrise.ClientTest do
  use ExUnit.Case, async: true

  import Mimic

  alias Tuist.Runners.Bitrise.Client
  alias Tuist.Runners.Bitrise.Connection

  setup :verify_on_exit!

  test "lists the workspaces a token sees" do
    expect(Req, :request, fn opts ->
      assert opts[:url] == "https://api.bitrise.io/v0.1/organizations"
      assert {"authorization", "bitwat_token"} in opts[:headers]

      {:ok,
       %{
         status: 200,
         body: %{"data" => [%{"name" => "Acme", "slug" => "6f7fab30975d4c3a", "owners" => []}]}
       }}
    end)

    assert {:ok, [%{slug: "6f7fab30975d4c3a", name: "Acme"}]} = Client.list_workspaces("bitwat_token")
  end

  test "lists only self-hosted pools among the workspace's stacks, by pool name" do
    expect(Req, :request, fn opts ->
      assert opts[:url] == "https://api.bitrise.io/v0.1/organizations/6f7fab30975d4c3a/available-stacks"

      {:ok,
       %{
         status: 200,
         body: %{
           "osx-xcode-26.4.x" => %{"id" => "osx-xcode-26.4.x", "title" => "Xcode 26.4.1"},
           "agent-pool-b" => %{"id" => "agent-pool-b", "title" => "Self-Hosted Runner: tuist-macos"},
           "agent-pool-a" => %{"id" => "agent-pool-a", "title" => "Self-Hosted Runner: tuist-linux"}
         }
       }}
    end)

    connection = %Connection{workspace_slug: "6f7fab30975d4c3a", api_token: "bitwat_token"}

    assert {:ok,
            [
              %{stack_identifier: "agent-pool-a", name: "tuist-linux"},
              %{stack_identifier: "agent-pool-b", name: "tuist-macos"}
            ]} = Client.list_self_hosted_pools(connection)
  end

  test "reads a build's slugs, stack and timestamps from the unfinished listing" do
    expect(Req, :request, fn opts ->
      assert opts[:url] == "https://api.bitrise.io/v0.1/builds"
      assert opts[:params][:owner_slug] == "6f7fab30975d4c3a"
      assert opts[:params][:status] == 0

      {:ok,
       %{
         status: 200,
         body: %{
           "data" => [
             %{
               "slug" => "3da87d70-71cd-48c0-8780-157e8c1c5801",
               "status" => 0,
               "stack_identifier" => "agent-pool-a",
               "machine_type_id" => "g2.mac.large",
               "triggered_at" => "2026-10-29T14:26:28Z",
               "started_on_worker_at" => nil,
               "is_on_hold" => false,
               "build_number" => 2,
               "branch" => "master",
               "commit_hash" => nil,
               "triggered_workflow" => "primary",
               "repository" => %{"slug" => "5782983d-2bc1-4627-a9b7-af2f2f390ed3", "title" => "Hello-World"}
             }
           ],
           "paging" => %{"total_item_count" => 0, "page_item_limit" => 50}
         }
       }}
    end)

    connection = %Connection{workspace_slug: "6f7fab30975d4c3a", api_token: "bitwat_token"}

    assert {:ok, [build]} = Client.list_unfinished_builds(connection)
    assert build.build_slug == "3da87d70-71cd-48c0-8780-157e8c1c5801"
    assert build.app_slug == "5782983d-2bc1-4627-a9b7-af2f2f390ed3"
    assert build.app_title == "Hello-World"
    assert build.stack_identifier == "agent-pool-a"
    assert build.commit_hash == ""
    assert build.started_on_worker_at == nil
    assert build.triggered_at == ~U[2026-10-29 14:26:28.000000Z]
  end
end
