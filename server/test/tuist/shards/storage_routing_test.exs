defmodule Tuist.Shards.StorageRoutingTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Runners.CacheGrant
  alias Tuist.Shards
  alias Tuist.Storage
  alias Tuist.Storage.ArtifactRetentionCursor
  alias Tuist.Storage.ExpiredArtifacts
  alias Tuist.Storage.S3Target
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures

  setup do
    project = ProjectsFixtures.project_fixture(build_system: :mix)
    key = {:okp, :Ed25519} |> JOSE.JWK.generate_key() |> JOSE.JWK.to_pem()
    key = if is_tuple(key), do: elem(key, 1), else: key
    stub(Environment, :cache_grant_private_key, fn -> key end)
    grant = CacheGrant.mint(project.account.id, site: "gra", platform: :linux)

    stub(Environment, :shard_storage_targets, fn ->
      %{
        "gra-v1" => %{
          "site" => "gra",
          "enabled" => true,
          "private_network_ready" => true,
          "endpoint" => "http://shard-storage.kura.svc.cluster.local:3900",
          "bucket" => "shards",
          "access_key_id" => "key",
          "secret_access_key" => "secret"
        }
      }
    end)

    %{project: project, account: project.account, opts: [runner_grant: grant]}
  end

  test "creation persists the target, and all reference/ID operations retain it after disabling the flag", ctx do
    stub(FeatureFlags, :runner_shard_storage_enabled?, fn _ -> true end)
    expect(Storage, :available?, fn _ -> true end)

    %{plan: plan} =
      Shards.create_shard_plan(ctx.project, %{reference: "local", modules: ["Tests"], shard_total: 1}, ctx.opts)

    assert {:ok, %{storage_target: "gra-v1"}} = Shards.get_shard_plan(plan.id)
    stub(FeatureFlags, :runner_shard_storage_enabled?, fn _ -> false end)
    reject(&Storage.object_exists?/2)
    key = Shards.bundle_object_key(ctx.account, ctx.project, plan.id)
    expect(Storage, :multipart_start, 2, fn ^key, %S3Target{id: "gra-v1"} -> {:ok, "upload"} end)
    expect(Storage, :multipart_generate_url, 2, fn ^key, "upload", 1, %S3Target{id: "gra-v1"} -> "put-url" end)
    expect(Storage, :multipart_complete_upload, 2, fn ^key, "upload", [{1, "etag"}], %S3Target{id: "gra-v1"} -> :ok end)
    expect(Storage, :generate_download_url, 2, fn ^key, %S3Target{id: "gra-v1"} -> "get-url" end)
    assert {:ok, "upload"} = Shards.start_upload(ctx.project, ctx.account, plan.reference, nil, ctx.opts)
    assert {:ok, "upload"} = Shards.start_upload_for_plan_id(ctx.project, ctx.account, plan.id, nil, ctx.opts)

    assert {:ok, "put-url"} =
             Shards.generate_upload_url(ctx.project, ctx.account, plan.reference, "upload", 1, nil, ctx.opts)

    assert {:ok, "put-url"} =
             Shards.generate_upload_url_for_plan(ctx.project, ctx.account, plan.id, "upload", 1, nil, ctx.opts)

    assert :ok = Shards.complete_upload(ctx.project, ctx.account, plan.reference, "upload", [{1, "etag"}], nil, ctx.opts)

    assert :ok =
             Shards.complete_upload_for_plan(ctx.project, ctx.account, plan.id, "upload", [{1, "etag"}], nil, ctx.opts)

    assert {:ok, %{download_url: "get-url"}} = Shards.get_shard(ctx.project, ctx.account, plan.reference, 0, ctx.opts)

    assert {:ok, %{download_url: "get-url"}} =
             Shards.get_shard_for_plan_id(ctx.project, ctx.account, plan.id, 0, ctx.opts)

    assert {:error, :shard_storage_site_required} = Shards.start_upload_for_plan_id(ctx.project, ctx.account, plan.id)
    assert {:error, :shard_storage_site_required} = Shards.get_shard_for_plan_id(ctx.project, ctx.account, plan.id, 0)
  end

  test "uploads a just-created plan to its store before any ClickHouse replica returns it", ctx do
    stub(FeatureFlags, :runner_shard_storage_enabled?, fn _ -> true end)
    expect(Storage, :available?, fn _ -> true end)

    %{plan: routed} =
      Shards.create_shard_plan(ctx.project, %{reference: "routed", modules: ["Tests"], shard_total: 1}, ctx.opts)

    stub(FeatureFlags, :runner_shard_storage_enabled?, fn _ -> false end)

    %{plan: default} =
      Shards.create_shard_plan(ctx.project, %{reference: "default", modules: ["Tests"], shard_total: 1}, ctx.opts)

    stub(Tuist.IngestRepo, :one, fn _queryable -> nil end)
    stub(Tuist.ClickHouseRepo, :one, fn _queryable -> nil end)
    routed_key = Shards.bundle_object_key(ctx.account, ctx.project, routed.id)
    default_key = Shards.bundle_object_key(ctx.account, ctx.project, default.id)
    account = ctx.account

    expect(Storage, :multipart_start, fn ^routed_key, %S3Target{id: "gra-v1"} -> {:ok, "routed"} end)
    expect(Storage, :multipart_generate_url, fn ^routed_key, "routed", 1, %S3Target{id: "gra-v1"} -> "routed-url" end)

    expect(Storage, :multipart_complete_upload, fn ^routed_key, "routed", [{1, "etag"}], %S3Target{id: "gra-v1"} ->
      :ok
    end)

    expect(Storage, :multipart_start, fn ^default_key, ^account -> {:ok, "default"} end)

    assert {:ok, "routed"} = Shards.start_upload_for_plan_id(ctx.project, ctx.account, routed.id, nil, ctx.opts)

    assert {:ok, "routed-url"} =
             Shards.generate_upload_url_for_plan(ctx.project, ctx.account, routed.id, "routed", 1, nil, ctx.opts)

    assert :ok =
             Shards.complete_upload_for_plan(ctx.project, ctx.account, routed.id, "routed", [{1, "etag"}], nil, ctx.opts)

    assert {:ok, "default"} = Shards.start_upload_for_plan_id(ctx.project, ctx.account, default.id, nil, ctx.opts)

    assert {:error, :not_found} =
             Shards.start_upload_for_plan_id(ProjectsFixtures.project_fixture(build_system: :mix), ctx.account, routed.id)
  end

  test "uploads a just-created plan by reference before any ClickHouse replica returns it", ctx do
    stub(FeatureFlags, :runner_shard_storage_enabled?, fn _ -> true end)
    expect(Storage, :available?, fn _ -> true end)
    xcode = ProjectsFixtures.project_fixture(build_system: :xcode, account_id: ctx.account.id)

    %{plan: routed} =
      Shards.create_shard_plan(ctx.project, %{reference: "routed", modules: ["Tests"], shard_total: 1}, ctx.opts)

    %{plan: default} = Shards.create_shard_plan(xcode, %{reference: "routed", modules: ["AppTests"], shard_total: 1})

    stub(Tuist.IngestRepo, :one, fn _queryable -> nil end)
    stub(Tuist.ClickHouseRepo, :one, fn _queryable -> nil end)
    routed_key = Shards.bundle_object_key(ctx.account, ctx.project, routed.id)
    default_key = Shards.bundle_object_key(ctx.account, xcode, default.id)
    account = ctx.account

    expect(Storage, :multipart_start, fn ^routed_key, %S3Target{id: "gra-v1"} -> {:ok, "routed"} end)
    expect(Storage, :multipart_generate_url, fn ^routed_key, "routed", 1, %S3Target{id: "gra-v1"} -> "routed-url" end)

    expect(Storage, :multipart_complete_upload, fn ^routed_key, "routed", [{1, "etag"}], %S3Target{id: "gra-v1"} ->
      :ok
    end)

    expect(Storage, :multipart_start, fn ^default_key, ^account -> {:ok, "default"} end)

    assert {:ok, "routed"} = Shards.start_upload(ctx.project, ctx.account, "routed", nil, ctx.opts)

    assert {:ok, "routed-url"} =
             Shards.generate_upload_url(ctx.project, ctx.account, "routed", "routed", 1, nil, ctx.opts)

    assert :ok = Shards.complete_upload(ctx.project, ctx.account, "routed", "routed", [{1, "etag"}], nil, ctx.opts)
    assert {:ok, "default"} = Shards.start_upload(xcode, ctx.account, "routed")
  end

  test "foreign and missing plan IDs cannot start, sign or complete an upload", ctx do
    foreign = ShardsFixtures.shard_plan_fixture()
    reject(&Storage.multipart_start/2)
    reject(&Storage.multipart_generate_url/4)
    reject(&Storage.multipart_complete_upload/4)

    for id <- [foreign.id, Ecto.UUID.generate()] do
      assert {:error, :not_found} = Shards.start_upload_for_plan_id(ctx.project, ctx.account, id)
      assert {:error, :not_found} = Shards.generate_upload_url_for_plan(ctx.project, ctx.account, id, "upload", 1)
      assert {:error, :not_found} = Shards.complete_upload_for_plan(ctx.project, ctx.account, id, "upload", [])
    end
  end

  test "cleanup routes by the plan and retries the same prefix after a deletion failure", ctx do
    plan =
      ShardsFixtures.shard_plan_fixture(
        project_id: ctx.project.id,
        storage_target: "gra-v1",
        inserted_at: DateTime.utc_now() |> DateTime.add(-8, :day) |> DateTime.to_naive()
      )

    prefix = Shards.plan_object_prefix(ctx.account, ctx.project, plan.id)
    expect(Storage, :delete_all_objects, fn ^prefix, %S3Target{id: "gra-v1"} -> {:error, :unavailable} end)
    assert {:error, :unavailable} = ExpiredArtifacts.delete_shard_bundles(ctx.account, 20, retention_days: 7)
    assert Repo.get_by(ArtifactRetentionCursor, account_id: ctx.account.id, artifact_type: :shard_bundle) == nil
    expect(Storage, :delete_all_objects, fn ^prefix, %S3Target{id: "gra-v1"} -> :ok end)
    assert {:ok, nil} = ExpiredArtifacts.delete_shard_bundles(ctx.account, 20, retention_days: 7)

    assert Repo.get_by!(ArtifactRetentionCursor, account_id: ctx.account.id, artifact_type: :shard_bundle).after_id ==
             plan.id
  end
end
