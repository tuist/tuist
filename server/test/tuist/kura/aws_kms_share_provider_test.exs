defmodule Tuist.Kura.VolumeKeys.AWSKMSShareProviderTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Kura.VolumeKeys
  alias Tuist.Kura.VolumeKeys.AWSKMSShareProvider
  alias Tuist.Kura.VolumeKeys.KMSHTTP
  alias Tuist.Kura.VolumeKeys.TenantKey
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @key "arn:aws:kms:eu-central-1:123456789012:key/11111111-1111-4111-8111-111111111111"
  @role "arn:aws:iam::123456789012:role/kura-staging"
  @sts "<AssumeRoleWithWebIdentityResponse><AssumeRoleWithWebIdentityResult><Credentials><AccessKeyId>access</AccessKeyId><SecretAccessKey>secret</SecretAccessKey><SessionToken>session</SessionToken></Credentials></AssumeRoleWithWebIdentityResult></AssumeRoleWithWebIdentityResponse>"

  setup do
    config = %{
      key_id: @key,
      decrypt_key_ids: [@key],
      region: "eu-central-1",
      role_arn: @role,
      token_file: "/test/kura-token"
    }

    stub(Environment, :kura_volume_kms, fn -> {:ok, config} end)
    stub(File, :read, fn "/test/kura-token" -> {:ok, "projected-token"} end)
    %{config: config}
  end

  test "pins the ARN, authenticates with projected identity and binds the encryption context" do
    plaintext = :crypto.strong_rand_bytes(32)

    expect(KMSHTTP, :post, 4, fn url, headers, content_type, body ->
      if String.contains?(url, "sts.") do
        assert URI.decode_query(body)["WebIdentityToken"] == "projected-token"
        assert URI.decode_query(body)["RoleArn"] == @role
        assert content_type == "application/x-www-form-urlencoded"
        {:ok, @sts}
      else
        assert url == "https://kms.eu-central-1.amazonaws.com/"
        assert Enum.any?(headers, fn {k, _} -> String.downcase(k) == "authorization" end)
        data = JSON.decode!(body)
        assert data["KeyId"] == @key
        assert data["EncryptionContext"] == %{"purpose" => "kura-volume-share", "aad" => "tenant|1|0"}

        if data["Plaintext"] do
          assert Base.decode64!(data["Plaintext"]) == plaintext
          {:ok, JSON.encode!(%{"KeyId" => @key, "CiphertextBlob" => Base.encode64("wrapped")})}
        else
          {:ok, JSON.encode!(%{"KeyId" => @key, "Plaintext" => Base.encode64(plaintext)})}
        end
      end
    end)

    assert {:ok, share} = AWSKMSShareProvider.wrap(plaintext, "tenant|1|0")
    assert AWSKMSShareProvider.unwrap(share, "tenant|1|0") == {:ok, plaintext}
  end

  test "refuses unapproved keys before any network request" do
    reject(&KMSHTTP.post/4)

    assert AWSKMSShareProvider.unwrap(%{"provider" => "aws_kms", "key_id" => "other", "ciphertext" => "abc"}, "aad") ==
             {:error, :kms_unavailable}
  end

  test "sanitizes failures and never exposes provider responses" do
    stub(KMSHTTP, :post, fn _, _, _, _ -> {:error, "sensitive provider error"} end)
    assert AWSKMSShareProvider.wrap(:crypto.strong_rand_bytes(32), "aad") == {:error, :kms_unavailable}
  end

  test "refuses a successful response for another key or malformed plaintext" do
    for response <- [
          %{"KeyId" => "wrong", "Plaintext" => Base.encode64(:crypto.strong_rand_bytes(32))},
          %{"KeyId" => @key, "Plaintext" => Base.encode64("short")}
        ] do
      stub(KMSHTTP, :post, fn url, _, _, _ ->
        if String.contains?(url, "sts."), do: {:ok, @sts}, else: {:ok, JSON.encode!(response)}
      end)

      assert AWSKMSShareProvider.unwrap(%{"provider" => "aws_kms", "key_id" => @key, "ciphertext" => "abc"}, "aad") ==
               {:error, :kms_unavailable}
    end
  end

  test "configuration requires a full key ARN and an explicit workload role" do
    assert :disabled = Environment.kura_volume_kms(%{})

    assert {:ok, %{region: "eu-central-1", decrypt_key_ids: [@key]}} =
             Environment.kura_volume_kms(%{
               "TUIST_KURA_VOLUME_KMS_KEY_ARN" => @key,
               "TUIST_KURA_VOLUME_KMS_ROLE_ARN" => @role
             })

    assert {:error, _} =
             Environment.kura_volume_kms(%{
               "TUIST_KURA_VOLUME_KMS_KEY_ARN" => "alias/kura",
               "TUIST_KURA_VOLUME_KMS_ROLE_ARN" => @role
             })

    assert {:error, _} = Environment.kura_volume_kms(%{"TUIST_KURA_VOLUME_KMS_KEY_ARN" => @key})
  end

  test "migrates a legacy share to KMS, fails closed during outage and recovers without changing the passphrase" do
    account = AccountsFixtures.account_fixture()
    root = :crypto.strong_rand_bytes(32)
    config = elem(Environment.kura_volume_kms(), 1)
    stub(Environment, :kura_volume_kms, fn -> :disabled end)
    stub(Environment, :kura_volume_root_keys, fn -> [{"legacy", root}] end)
    {:ok, key} = VolumeKeys.ensure_active_key(account)
    {:ok, passphrase} = VolumeKeys.volume_passphrase(account, key, "pvc-recovery")

    stub(Environment, :kura_volume_kms, fn -> {:ok, config} end)
    kms_root = :crypto.strong_rand_bytes(32)
    kms = fake_kms(kms_root)
    stub(KMSHTTP, :post, kms)
    assert :ok = VolumeKeys.rewrap_key(key.id, {"aws_kms", @key})
    wrapped = Repo.reload!(key)
    assert [%{"provider" => "aws_kms", "key_id" => @key}] = wrapped.shares
    stub(Environment, :kura_volume_root_keys, fn -> [] end)
    assert VolumeKeys.volume_passphrase(account, wrapped, "pvc-recovery") == {:ok, passphrase}

    stub(KMSHTTP, :post, fn _, _, _, _ -> {:error, :kms_unavailable} end)
    assert VolumeKeys.volume_passphrase(account, wrapped, "pvc-recovery") == {:error, :kms_unavailable}
    assert {:error, :kms_unavailable} = VolumeKeys.rewrap_key(key.id, {"aws_kms", @key})
    assert Repo.reload!(key).shares == wrapped.shares
    stub(KMSHTTP, :post, kms)
    assert VolumeKeys.volume_passphrase(account, Repo.reload!(key), "pvc-recovery") == {:ok, passphrase}
  end

  test "a concurrent change cannot be overwritten by a completed rewrap" do
    account = AccountsFixtures.account_fixture()
    root = :crypto.strong_rand_bytes(32)
    config = elem(Environment.kura_volume_kms(), 1)
    stub(Environment, :kura_volume_kms, fn -> :disabled end)
    stub(Environment, :kura_volume_root_keys, fn -> [{"legacy", root}] end)
    {:ok, key} = VolumeKeys.ensure_active_key(account)
    winner = Enum.map(key.shares, &Map.put(&1, "migration_marker", "concurrent-winner"))
    stub(Environment, :kura_volume_kms, fn -> {:ok, config} end)
    kms = fake_kms(:crypto.strong_rand_bytes(32))

    stub(KMSHTTP, :post, fn url, headers, type, body ->
      if String.contains?(url, "kms.") and JSON.decode!(body)["Plaintext"] do
        Repo.update_all(from(k in TenantKey, where: k.id == ^key.id), set: [shares: winner])
      end

      kms.(url, headers, type, body)
    end)

    assert {:error, :concurrent_key_change} = VolumeKeys.rewrap_key(key.id, {"aws_kms", @key})
    assert Repo.reload!(key).shares == winner
  end

  # Local cryptographic stand-in for KMS, not a claim of live AWS validation.
  defp fake_kms(root) do
    fn url, _, _, body ->
      if String.contains?(url, "sts.") do
        {:ok, @sts}
      else
        data = JSON.decode!(body)
        aad = data["EncryptionContext"]["aad"]

        if data["Plaintext"] do
          nonce = :crypto.strong_rand_bytes(12)

          {ciphertext, tag} =
            :crypto.crypto_one_time_aead(:aes_256_gcm, root, nonce, Base.decode64!(data["Plaintext"]), aad, 16, true)

          {:ok, JSON.encode!(%{"KeyId" => data["KeyId"], "CiphertextBlob" => Base.encode64(nonce <> ciphertext <> tag)})}
        else
          <<nonce::binary-size(12), ciphertext::binary-size(32), tag::binary-size(16)>> =
            Base.decode64!(data["CiphertextBlob"])

          plaintext = :crypto.crypto_one_time_aead(:aes_256_gcm, root, nonce, ciphertext, aad, tag, false)
          {:ok, JSON.encode!(%{"KeyId" => data["KeyId"], "Plaintext" => Base.encode64(plaintext)})}
        end
      end
    end
  end
end
