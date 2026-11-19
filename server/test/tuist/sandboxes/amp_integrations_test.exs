defmodule Tuist.Sandboxes.AmpIntegrationsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Sandboxes.AmpIntegrations
  alias Tuist.Sandboxes.AmpRuntime

  setup do
    user = user_fixture()
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> true end)
    %{user: user, account: user.account}
  end

  test "encrypts credentials, persists provisioning, and never returns secrets in public status", %{
    user: user,
    account: account
  } do
    token = "aop_live_#{Ecto.UUID.generate()}"
    assert {:ok, integration} = AmpIntegrations.connect(account.id, user, token)
    assert integration.provider_token == token

    assert [[encrypted]] =
             Repo.query!("SELECT provider_token FROM amp_integrations WHERE account_id=$1", [account.id]).rows

    refute encrypted == token
    refute inspect(integration) =~ token
    refute Map.has_key?(AmpIntegrations.public_status(integration), :provider_token)
    assert_enqueued(worker: Tuist.Sandboxes.AmpReconciler, args: %{"account_id" => account.id})
  end

  test "only administrators can connect or disconnect", %{account: account, user: user} do
    other = user_fixture()
    assert {:error, _} = AmpIntegrations.connect(account.id, other, "aop_live_valid")
    assert {:ok, _} = AmpIntegrations.connect(account.id, user, "aop_live_valid")
    assert {:error, _} = AmpIntegrations.disconnect(account.id, other)
    assert AmpIntegrations.get(account.id).enabled
  end

  test "flag denial prevents connection but never prevents disconnect", %{account: account, user: user} do
    assert {:ok, _} = AmpIntegrations.connect(account.id, user, "aop_live_valid")
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> false end)
    assert {:error, :disabled} = AmpIntegrations.connect(account.id, user, "aop_live_new")
    assert {:ok, disconnected} = AmpIntegrations.disconnect(account.id, user)
    refute disconnected.enabled
    assert is_nil(disconnected.provider_token)
    assert disconnected.status == :disconnecting
  end

  test "a provider token cannot be shared across Tuist accounts", %{account: account, user: user} do
    other = user_fixture()
    assert {:ok, _} = AmpIntegrations.connect(account.id, user, "aop_live_unique")
    assert {:error, %Ecto.Changeset{}} = AmpIntegrations.connect(other.account.id, other, "aop_live_unique")
    refute AmpIntegrations.get(other.account.id)
  end

  test "rotation preserves integration and changes the authorized workload identity", %{account: account, user: user} do
    assert {:ok, first} = AmpIntegrations.connect(account.id, user, "aop_live_first")
    assert {:ok, second} = AmpIntegrations.connect(account.id, user, "aop_live_second")
    assert first.id == second.id
    refute AmpRuntime.name(first) == AmpRuntime.name(second)
    assert second.status == :pending
  end

  test "rejects malformed and oversized credentials", %{account: account, user: user} do
    for token <- ["", "not-an-amp-token", "aop_live_bad\nheader", String.duplicate("a", 4097)] do
      assert {:error, _} = AmpIntegrations.connect(account.id, user, token)
    end

    refute AmpIntegrations.get(account.id)
  end

  test "runtime has no human login or persistent credentials and only a dedicated audience", %{
    account: account,
    user: user
  } do
    {:ok, integration} = AmpIntegrations.connect(account.id, user, "aop_live_manifest")
    config = %{namespace: "amp", image: "image:immutable", url: "https://example.test", node_selector: %{}}
    [sa, secret, deployment] = AmpRuntime.manifests(integration, config)
    refute sa["automountServiceAccountToken"]
    assert secret["data"]["amp-token"] == Base.encode64("aop_live_manifest")
    pod = deployment["spec"]["template"]["spec"]
    assert pod["serviceAccountName"] == AmpRuntime.name(integration)

    assert Enum.find(pod["volumes"], &(&1["name"] == "identity"))["projected"]["sources"] == [
             %{"serviceAccountToken" => %{"audience" => "tuist-amp-orbs", "expirationSeconds" => 3600, "path" => "token"}}
           ]

    refute inspect(deployment) =~ "aop_live_manifest"
    refute inspect(deployment) =~ "persistentVolumeClaim"
    refute inspect(deployment) =~ "TUIST_ACCOUNT"
  end
end
