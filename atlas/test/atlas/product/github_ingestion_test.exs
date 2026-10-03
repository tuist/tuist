defmodule Atlas.Product.GitHubIngestionTest do
  use Atlas.DataCase, async: true

  alias Atlas.Integrations
  alias Atlas.Product
  alias Atlas.Product.Briefs.Adapter
  alias Atlas.Product.GitHubIngestion

  test "records configured pull request traces idempotently" do
    _repository = insert_repository!()
    payload = pull_request_payload("opened", false)

    assert {:ok, first} = GitHubIngestion.ingest("pull_request", payload)
    assert first.kind == "pull_request_opened"
    assert first.labels == ["release"]

    assert {:ok, duplicate} = GitHubIngestion.ingest("pull_request", payload)
    assert duplicate.id == first.id

    {traces, meta} = Product.list_traces()
    assert meta.total_count == 1
    assert Enum.map(traces, & &1.id) == [first.id]
  end

  test "the product adapter excludes pull requests that later closed" do
    _repository = insert_repository!()

    assert {:ok, stale} = GitHubIngestion.ingest("pull_request", pull_request_payload("opened", false))
    assert {:ok, _closed} = GitHubIngestion.ingest("pull_request", pull_request_payload("closed", false))

    period = %{start_at: ~U[2026-07-13 00:00:00Z], end_at: ~U[2026-07-21 00:00:00Z]}
    assert {:ok, result} = Adapter.candidate_items("weekly", period)

    refute Enum.any?(result.items, &(&1.fingerprint == "product:stale_pull_request:#{stale.github_repository_id}:42"))
  end

  test "the product adapter links brief items to their GitHub evidence" do
    _repository = insert_repository!()

    assert {:ok, trace} = GitHubIngestion.ingest("pull_request", pull_request_payload("closed", true))

    period = %{start_at: ~U[2026-07-13 00:00:00Z], end_at: ~U[2026-07-21 00:00:00Z]}
    assert {:ok, result} = Adapter.candidate_items("weekly", period)

    assert [%{source_path: source_path}] = result.items
    assert source_path == trace.url
  end

  test "ignores repositories that are not configured" do
    assert :ignored = GitHubIngestion.ingest("pull_request", pull_request_payload("opened", false))
  end

  test "only ingests repositories owned by the app whose webhook was verified" do
    {:ok, verifying_app} =
      Integrations.create_github_app(%{
        name: "Verifying app",
        webhook_secret: "verifying-secret",
        app_id: "verifying-#{System.unique_integer([:positive])}",
        private_key: "private-key",
        installation_id: "verifying-#{System.unique_integer([:positive])}"
      })

    {:ok, other_app} =
      Integrations.create_github_app(%{
        name: "Other app",
        webhook_secret: "other-secret",
        app_id: "other-#{System.unique_integer([:positive])}",
        private_key: "private-key",
        installation_id: "other-#{System.unique_integer([:positive])}"
      })

    {:ok, _repository} = Integrations.add_github_repository(other_app, %{owner: "tuist", repo: "atlas"})

    assert :ignored =
             GitHubIngestion.ingest("pull_request", pull_request_payload("opened", false),
               github_app_id: verifying_app.id
             )

    assert {_traces, %{total_count: 0}} = Product.list_traces()
  end

  defp insert_repository! do
    {:ok, app} =
      Integrations.create_github_app(%{
        name: "Product trace app",
        webhook_secret: "secret",
        app_id: "#{System.unique_integer([:positive])}",
        private_key: "private-key",
        installation_id: "#{System.unique_integer([:positive])}"
      })

    {:ok, repository} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "atlas"})
    repository
  end

  defp pull_request_payload(action, merged?) do
    %{
      "action" => action,
      "repository" => %{
        "name" => "atlas",
        "full_name" => "tuist/atlas",
        "owner" => %{"login" => "tuist"}
      },
      "pull_request" => %{
        "id" => 1_001,
        "number" => 42,
        "title" => "Prepare the release",
        "html_url" => "https://github.com/tuist/atlas/pull/42",
        "created_at" => "2026-07-01T10:00:00Z",
        "closed_at" => if(action == "closed", do: "2026-07-20T10:00:00Z"),
        "merged_at" => if(merged?, do: "2026-07-20T10:00:00Z"),
        "merged" => merged?,
        "user" => %{"login" => "octocat"},
        "labels" => [%{"name" => "release"}]
      }
    }
  end
end
