defmodule Tuist.CacheE2ETokenTest do
  @moduledoc """
  Mints a cache token the way production does, signed with the secret Kura's
  extension tests verify with, and writes it where the Rust side can pick it up.
  Run together with the kura test that reads it; see kura/scripts/cache-token-e2e.sh.
  """
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Cache
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @tag :e2e_cache_token
  test "writes a cache token for acme/ios" do
    path = System.get_env("CACHE_TOKEN_OUT") || raise "CACHE_TOKEN_OUT not set"

    previous = Application.get_env(:tuist, Tuist.Guardian)

    Application.put_env(:tuist, Tuist.Guardian,
      issuer: "tuist",
      secret_key: "tuist-guardian-secret"
    )

    on_exit(fn -> Application.put_env(:tuist, Tuist.Guardian, previous) end)

    organization = AccountsFixtures.organization_fixture(name: "acme", preload: [:account])
    project = ProjectsFixtures.project_fixture(account: organization.account, name: "ios")

    {:ok, token, claims} = Cache.issue_cache_token(project)

    assert claims["cache_grants"]["project"]["read"] == ["acme/ios"]
    File.write!(path, token)
  end
end
