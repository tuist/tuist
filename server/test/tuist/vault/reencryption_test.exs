defmodule Tuist.Vault.ReencryptionTest do
  # Not async: it restarts the application's vault with other keys.
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Cloak.Ciphers.AES.GCM
  alias Tuist.Accounts.Account
  alias Tuist.Automations.Workers.SlackNotificationWorker
  alias Tuist.Release
  alias Tuist.Slack
  alias Tuist.Slack.Client
  alias Tuist.Vault.Reencryption
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AutomationsFixtures

  setup do
    [{"V1", legacy_key} | _] = Tuist.Environment.encryption_keys()

    # The test runs its own vault in place of the application's, and puts the
    # application's back once the test's is stopped.
    :ok = Supervisor.terminate_child(Tuist.Supervisor, Tuist.Vault)
    on_exit(fn -> {:ok, _pid} = Supervisor.restart_child(Tuist.Supervisor, Tuist.Vault) end)
    use_keys([{"V1", legacy_key}])

    %{legacy_key: legacy_key, new_key: :crypto.strong_rand_bytes(32)}
  end

  test "finds the encrypted fields from the schemas, with their tables' primary keys" do
    tables = Map.new(Reencryption.tables(), &{&1.table, &1})

    assert %{primary_key: ["id"], columns: ["s3_access_key_id", "s3_secret_access_key"]} = tables["accounts"]
    assert %{columns: ["secret"]} = tables["user_mfa"]
    assert tables["projects"].columns == ["flaky_test_alerts_slack_webhook_url", "slack_webhook_url"]
  end

  test "rotates every value to the new key, after which the old key is no longer needed to read them", %{
    legacy_key: legacy_key,
    new_key: new_key
  } do
    secrets = for n <- 1..5, do: "secret-#{n}"
    accounts = Enum.map(secrets, &store_secret(AccountsFixtures.account_fixture(), &1))
    unset = AccountsFixtures.account_fixture()

    assert Enum.all?(accounts, &(tag(&1) == "AES.GCM.V1"))

    # Without the old key, the values stored under it cannot be read: the
    # control that makes the read after rotating meaningful.
    use_keys([{"k2", new_key}])
    assert_raise ArgumentError, fn -> Repo.get!(Account, hd(accounts).id) end

    use_keys([{"k2", new_key}, {"V1", legacy_key}])
    counts = Release.reencrypt_vault("k2", batch_size: 2)

    assert counts["accounts.s3_secret_access_key"] == %{reencrypted: 5, changed: 0, failed: 0}
    assert Enum.all?(accounts, &(tag(&1) == "AES.GCM.k2"))
    assert raw(unset) == nil

    use_keys([{"k2", new_key}])

    assert Enum.map(accounts, &Repo.get!(Account, &1.id).s3_secret_access_key) == secrets

    # A rerun finds nothing left, which is what makes an interrupted run resumable.
    assert Release.reencrypt_vault("k2")["accounts.s3_secret_access_key"] == %{reencrypted: 0, changed: 0, failed: 0}
  end

  test "refuses to run unless the node already encrypts with the given key", %{legacy_key: legacy_key} do
    use_keys([{"V1", legacy_key}])

    assert_raise RuntimeError, ~r/encrypts with AES.GCM.V1, not AES.GCM.k2/, fn ->
      Release.reencrypt_vault("k2")
    end
  end

  test "rotates what it can and fails the run, without logging key material, when values cannot be decrypted", %{
    legacy_key: legacy_key,
    new_key: new_key
  } do
    readable = store_secret(AccountsFixtures.account_fixture(), "readable")
    unknown_tag = AccountsFixtures.account_fixture()
    wrong_key = AccountsFixtures.account_fixture()

    # A tag no configured key has, and the current tag under a key that is not
    # the configured one, which Cloak reports as `{:ok, :error}`.
    {:ok, foreign} = GCM.encrypt("foreign", tag: "AES.GCM.gone", key: :crypto.strong_rand_bytes(32))
    {:ok, forged} = GCM.encrypt("forged", tag: "AES.GCM.V1", key: :crypto.strong_rand_bytes(32))
    Repo.query!("UPDATE accounts SET s3_secret_access_key = $1 WHERE id = $2", [foreign, unknown_tag.id])
    Repo.query!("UPDATE accounts SET s3_secret_access_key = $1 WHERE id = $2", [forged, wrong_key.id])

    use_keys([{"k2", new_key}, {"V1", legacy_key}])

    log =
      capture_log(fn ->
        error = assert_raise RuntimeError, fn -> Release.reencrypt_vault("k2") end
        assert error.message =~ "accounts.s3_secret_access_key (2)"
      end)

    refute log =~ inspect(new_key)
    refute log =~ inspect(legacy_key)
    assert tag(readable) == "AES.GCM.k2"
    assert raw(unknown_tag) == foreign
    assert raw(wrong_key) == forged
  end

  test "rotates Slack webhook URLs inside automation actions without cancelling notifications queued before", %{
    legacy_key: legacy_key,
    new_key: new_key
  } do
    url = "https://hooks.slack.com/services/rotated"
    {:ok, encrypted} = Slack.encrypt_webhook_url(url)
    channel = %{"type" => "send_slack", "channel" => "C1", "message" => "Alert"}

    webhook = %{
      "type" => "send_slack",
      "channel" => "#alerts",
      "message" => "Alert",
      "webhook_url_encrypted" => encrypted
    }

    alert = AutomationsFixtures.automation_alert_fixture(trigger_actions: [channel, webhook])
    queued = %Oban.Job{args: %{"alert_id" => alert.id, "action" => webhook, "blocks" => []}}

    use_keys([{"k2", new_key}, {"V1", legacy_key}])
    counts = Release.reencrypt_vault("k2")

    assert counts["automation_alerts.trigger_actions"] == %{reencrypted: 1, changed: 0, failed: 0}
    assert Release.reencrypt_vault("k2")["automation_alerts.trigger_actions"].reencrypted == 0

    %{rows: [[[^channel, rotated]]]} =
      Repo.query!("SELECT trigger_actions FROM automation_alerts WHERE id = $1", [Ecto.UUID.dump!(alert.id)])

    # The queued job still holds the V1 ciphertext, so matching actions by
    # ciphertext would have cancelled it.
    assert rotated["webhook_url_encrypted"] != encrypted
    expect(Client, :deliver_once, fn {:webhook, ^url}, [] -> :ok end)
    assert :ok = SlackNotificationWorker.perform(queued)

    use_keys([{"k2", new_key}])
    assert {:ok, ^url} = Slack.decrypt_webhook_url(rotated["webhook_url_encrypted"])
  end

  defp store_secret(account, secret) do
    account |> Ecto.Changeset.change(s3_secret_access_key: secret) |> Repo.update!()
  end

  defp raw(account) do
    %{rows: [[value]]} = Repo.query!("SELECT s3_secret_access_key FROM accounts WHERE id = $1", [account.id])
    value
  end

  defp tag(account) do
    <<1, length, tag::binary-size(length), _rest::binary>> = raw(account)
    tag
  end

  defp use_keys(keys) do
    stop_supervised(Tuist.Vault)
    start_supervised!({Tuist.Vault, keys: keys})
  end
end
