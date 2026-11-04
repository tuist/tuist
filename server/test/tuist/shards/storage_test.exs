defmodule Tuist.Shards.StorageTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Projects.Project
  alias Tuist.Runners.CacheGrant
  alias Tuist.Shards.ShardPlan
  alias Tuist.Shards.Storage, as: ShardStorage
  alias Tuist.Storage
  alias Tuist.Storage.S3Target

  setup do
    config = %{
      "site" => "gra",
      "enabled" => true,
      "private_network_ready" => true,
      "endpoint" => "http://shard-storage.kura.svc.cluster.local:3900",
      "bucket" => "shards",
      "access_key_id" => "test-key",
      "secret_access_key" => "test-secret"
    }

    stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => config} end)
    stub(FeatureFlags, :runner_shard_storage_enabled?, fn _ -> true end)
    key = JOSE.JWK.generate_key({:okp, :Ed25519})
    pem = JOSE.JWK.to_pem(key)
    pem = if is_tuple(pem), do: elem(pem, 1), else: pem
    stub(Environment, :cache_grant_private_key, fn -> pem end)
    grant = CacheGrant.mint(42, site: "gra", platform: :linux)
    %{config: config, account: %Account{id: 42}, project: %Project{build_system: :mix}, grant: grant}
  end

  test "selects a ready store only for an enrolled signed Linux runner", ctx do
    expect(Storage, :available?, fn %S3Target{id: "gra-v1"} -> true end)
    assert ShardStorage.select(ctx.project, ctx.account, ctx.grant) == "gra-v1"
  end

  test "fails back before persistence when readiness fails", ctx do
    expect(Storage, :available?, fn _ -> false end)
    assert ShardStorage.select(ctx.project, ctx.account, ctx.grant) == ""
  end

  test "unverified, foreign-account, macOS, and legacy grants never probe the store", ctx do
    reject(&Storage.available?/1)

    for grant <- [
          nil,
          "forged",
          CacheGrant.mint(43, site: "gra", platform: :linux),
          CacheGrant.mint(42, site: "gra", platform: :macos),
          CacheGrant.mint(42)
        ] do
      assert ShardStorage.select(ctx.project, ctx.account, grant) == ""
    end

    assert ShardStorage.select(%Project{build_system: :xcode}, ctx.account, ctx.grant) == ""
  end

  test "disabled flag and unconfirmed transport keep new plans on default storage", ctx do
    reject(&Storage.available?/1)
    stub(FeatureFlags, :runner_shard_storage_enabled?, fn _ -> false end)
    assert ShardStorage.select(ctx.project, ctx.account, ctx.grant) == ""
    stub(FeatureFlags, :runner_shard_storage_enabled?, fn _ -> true end)
    stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => %{ctx.config | "private_network_ready" => false}} end)
    assert ShardStorage.select(ctx.project, ctx.account, ctx.grant) == ""
  end

  test "a persisted target survives disabled enrollment, uses path-style S3, and never rechecks readiness", ctx do
    reject(&Storage.available?/1)
    stub(Environment, :shard_storage_targets, fn -> %{"gra-v1" => %{ctx.config | "enabled" => false}} end)
    assert {:ok, target} = ShardStorage.resolve(%ShardPlan{storage_target: "gra-v1"}, ctx.account)

    assert URI.parse(Storage.generate_download_url("42/1/shards/plan/bundle.zip", target)).host ==
             "shard-storage.kura.svc.cluster.local"

    assert URI.parse(Storage.generate_download_url("42/1/shards/plan/bundle.zip", target)).path ==
             "/shards/42/1/shards/plan/bundle.zip"
  end

  test "missing configuration never redirects a persisted plan", ctx do
    assert {:error, :shard_storage_unavailable} = ShardStorage.resolve(%ShardPlan{storage_target: "removed"}, ctx.account)
    assert {:ok, ctx.account} == ShardStorage.resolve(%ShardPlan{}, ctx.account)
  end

  test "local artifacts require the original site on consumers too", ctx do
    plan = %ShardPlan{storage_target: "gra-v1"}
    assert {:ok, %S3Target{}} = ShardStorage.resolve_for_request(plan, ctx.account, ctx.grant)

    for grant <- [nil, CacheGrant.mint(42, site: "other", platform: :linux)] do
      assert {:error, :shard_storage_unavailable} = ShardStorage.resolve_for_request(plan, ctx.account, grant)
    end
  end

  test "custom account storage remains authoritative for new plans", ctx do
    reject(&Storage.available?/1)
    account = %{ctx.account | s3_bucket_name: "custom", s3_access_key_id: "key", s3_secret_access_key: "secret"}
    assert ShardStorage.select(ctx.project, account, ctx.grant) == ""
    assert {:ok, ^account} = ShardStorage.resolve(%ShardPlan{}, account)
  end
end
