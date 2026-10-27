defmodule Atlas.Push.ConfigTest do
  use ExUnit.Case, async: true
  use Mimic

  import Atlas.PushFixtures

  alias Atlas.Push.Config

  defp apns_env(overrides \\ %{}) do
    Map.merge(
      %{
        "ATLAS_APNS_TEAM_ID" => "TEAM123456",
        "ATLAS_APNS_KEY_ID" => "KEY1234567",
        "ATLAS_APNS_PRIVATE_KEY" => ec_pem()
      },
      overrides
    )
  end

  defp fcm_env(account_overrides \\ %{}) do
    account =
      Map.merge(
        %{
          "type" => "service_account",
          "project_id" => "atlas-push-test",
          "client_email" => "push@atlas-push-test.iam.gserviceaccount.com",
          "private_key" => rsa_pem(),
          "token_uri" => "https://attacker.example/token"
        },
        account_overrides
      )

    %{"ATLAS_FCM_SERVICE_ACCOUNT_JSON" => JSON.encode!(account)}
  end

  test "unset or blank providers are unavailable" do
    assert Config.parse!(%{}) == [apns: nil, fcm: nil]

    assert Config.parse!(%{"ATLAS_APNS_TEAM_ID" => " ", "ATLAS_FCM_SERVICE_ACCOUNT_JSON" => ""}) == [
             apns: nil,
             fcm: nil
           ]
  end

  test "parses complete credentials without keeping the service account's token endpoint" do
    config = Config.parse!(Map.merge(apns_env(), fcm_env()))

    assert %{team_id: "TEAM123456", key_id: "KEY1234567", environment: "production"} = config[:apns]

    assert config[:fcm] == %{
             project_id: "atlas-push-test",
             client_email: "push@atlas-push-test.iam.gserviceaccount.com",
             private_key: rsa_pem()
           }
  end

  test "APNs credentials only authorize their configured environment" do
    for environment <- ["production", "sandbox", "both"] do
      apns = Config.parse!(apns_env(%{"ATLAS_APNS_ENVIRONMENT" => environment}))[:apns]
      stub(Config, :apns, fn -> {:ok, apns} end)

      for target <- ["production", "sandbox"] do
        assert Config.available?("ios", target) == environment in ["both", target]
      end
    end
  end

  test "partial or malformed credentials fail without echoing secrets" do
    invalid = [
      Map.delete(apns_env(), "ATLAS_APNS_KEY_ID"),
      apns_env(%{"ATLAS_APNS_TEAM_ID" => "team"}),
      apns_env(%{"ATLAS_APNS_ENVIRONMENT" => "secret-material"}),
      apns_env(%{
        "ATLAS_APNS_PRIVATE_KEY" => "-----BEGIN PRIVATE KEY-----\nsecret-material\n-----END PRIVATE KEY-----"
      }),
      apns_env(%{"ATLAS_APNS_PRIVATE_KEY" => rsa_pem()}),
      %{"ATLAS_FCM_SERVICE_ACCOUNT_JSON" => "secret-material"},
      fcm_env(%{"type" => "authorized_user"}),
      fcm_env(%{"project_id" => "Bad Project"}),
      fcm_env(%{"private_key" => ec_pem()})
    ]

    for env <- invalid do
      error = assert_raise RuntimeError, fn -> Config.parse!(env) end
      refute error.message =~ "secret-material"
      refute error.message =~ "PRIVATE KEY"
    end
  end
end
