defmodule Tuist.CacheE2ETokenTest do
  @moduledoc """
  Mints a cache token the way production does and writes it where the Rust side
  can pick it up. Only runs as part of kura/scripts/cache-token-e2e.sh, which
  pins TUIST_SECRET_KEY_TOKENS to the secret Kura's extension tests verify with.
  """
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Cache
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @tag :e2e_cache_token
  test "writes a cache token for acme/ios" do
    path = System.get_env("CACHE_TOKEN_OUT") || raise "CACHE_TOKEN_OUT not set"

    organization = AccountsFixtures.organization_fixture(name: "acme", preload: [:account])
    project = ProjectsFixtures.project_fixture(account: organization.account, name: "ios")

    {:ok, token, claims} = Cache.issue_cache_token(project)

    assert claims["cache_grants"]["project"]["read"] == ["acme/ios"]
    File.write!(path, token)
  end
end
