defmodule Tuist.Kura.VolumeKeys.OpenBaoShareProviderTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Kura.VolumeKeys
  alias Tuist.Kura.VolumeKeys.KeyServiceHTTP
  alias Tuist.Kura.VolumeKeys.OpenBaoShareProvider
  alias Tuist.Kura.VolumeKeys.Rotation
  alias Tuist.Kura.VolumeKeys.TenantKey
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @address "https://openbao.example.test:8200"
  @key "#{@address}/v1/transit/keys/kura-volume-root"
  @environment %{
    "TUIST_KURA_VOLUME_OPENBAO_ADDRESS" => @address,
    "TUIST_KURA_VOLUME_OPENBAO_KEY_NAME" => "kura-volume-root",
    "TUIST_KURA_VOLUME_OPENBAO_ROLE" => "kura-staging",
    "TUIST_KURA_VOLUME_OPENBAO_TOKEN_FILE" => "/test/kura-token"
  }

  setup do
    {:ok, config} = Environment.kura_volume_openbao(@environment)
    stub(Environment, :kura_volume_openbao, fn -> {:ok, config} end)
    stub(File, :read, fn "/test/kura-token" -> {:ok, "projected-token\n"} end)
    %{config: config}
  end

  test "pins the backend and authenticates each operation with projected identity" do
    plaintext = :crypto.strong_rand_bytes(32)
    ciphertext = "vault:v1:" <> Base.encode64("wrapped")

    expect(File, :read, 2, fn "/test/kura-token" -> {:ok, "fresh-projected-token\n"} end)

    expect(KeyServiceHTTP, :post, 4, fn url, headers, "application/json", body, nil ->
      data = JSON.decode!(body)

      case url do
        @address <> "/v1/auth/kubernetes/login" ->
          assert data == %{"role" => "kura-staging", "jwt" => "fresh-projected-token"}
          assert headers == []
          {:ok, JSON.encode!(%{"auth" => %{"client_token" => "short-lived-token"}})}

        @address <> "/v1/transit/" <> operation ->
          assert headers == [{"X-Vault-Token", "short-lived-token"}]
          assert Base.decode64!(data["context"]) == "tenant|1|0"
          assert data["associated_data"] == data["context"]

          case operation do
            "encrypt/kura-volume-root" ->
              assert Base.decode64!(data["plaintext"]) == plaintext
              {:ok, JSON.encode!(%{"data" => %{"ciphertext" => ciphertext}})}

            "decrypt/kura-volume-root" ->
              assert data["ciphertext"] == ciphertext
              {:ok, JSON.encode!(%{"data" => %{"plaintext" => Base.encode64(plaintext)}})}
          end
      end
    end)

    assert {:ok, %{"provider" => "openbao", "key_id" => @key} = share} =
             OpenBaoShareProvider.wrap(plaintext, "tenant|1|0")

    assert OpenBaoShareProvider.unwrap(share, "tenant|1|0") == {:ok, plaintext}
  end

  test "refuses other origins, mounts, keys and malformed ciphertext before any request" do
    reject(&KeyServiceHTTP.post/5)

    for key <- ["https://attacker.test/v1/transit/keys/kura-volume-root", @key <> "-old", "../kura-volume-root"] do
      assert OpenBaoShareProvider.unwrap(share(key), "aad") == {:error, :key_service_unavailable}
    end

    for ciphertext <- ["abc", "vault:v0:YWJj", "vault:v1:!", "vault:v1:"] do
      assert OpenBaoShareProvider.unwrap(Map.put(share(@key), "ciphertext", ciphertext), "aad") ==
               {:error, :key_service_unavailable}
    end
  end

  test "a configured old key can decrypt but is not used for new shares", %{config: config} do
    old_id = @key <> "-old"
    config = put_in(config.decrypt_keys[old_id], "kura-volume-root-old")
    stub(KeyServiceHTTP, :post, fake_openbao(:crypto.strong_rand_bytes(32)))
    plaintext = :crypto.strong_rand_bytes(32)
    stub(Environment, :kura_volume_openbao, fn -> {:ok, %{config | key_id: old_id, key_name: "kura-volume-root-old"}} end)
    {:ok, old_wrapped} = OpenBaoShareProvider.wrap(plaintext, "aad")
    stub(Environment, :kura_volume_openbao, fn -> {:ok, config} end)
    {:ok, wrapped} = OpenBaoShareProvider.wrap(plaintext, "aad")
    assert wrapped["key_id"] == @key
    assert {:ok, ^plaintext} = OpenBaoShareProvider.unwrap(old_wrapped, "aad")
    assert {:error, :key_service_unavailable} = OpenBaoShareProvider.unwrap(Map.put(wrapped, "key_id", old_id), "aad")
  end

  test "sanitizes transport failures, malformed responses and exceptions" do
    for response <- [
          {:error, "sensitive provider error"},
          {:ok, "sensitive invalid JSON"},
          {:ok, JSON.encode!(%{"auth" => %{"client_token" => ""}})},
          {:ok, JSON.encode!(%{"errors" => ["secret"]})}
        ] do
      stub(KeyServiceHTTP, :post, fn _, _, _, _, _ -> response end)
      assert OpenBaoShareProvider.wrap(:crypto.strong_rand_bytes(32), "aad") == {:error, :key_service_unavailable}
    end

    stub(KeyServiceHTTP, :post, fn _, _, _, _, _ -> raise "secret token" end)
    assert OpenBaoShareProvider.wrap(:crypto.strong_rand_bytes(32), "aad") == {:error, :key_service_unavailable}
  end

  test "missing or empty projected identity never reaches OpenBao" do
    reject(&KeyServiceHTTP.post/5)

    for result <- [{:error, :enoent}, {:ok, "\n"}] do
      stub(File, :read, fn _ -> result end)
      assert OpenBaoShareProvider.wrap(:crypto.strong_rand_bytes(32), "aad") == {:error, :key_service_unavailable}
    end
  end

  test "rejects malformed successful decrypt responses" do
    for plaintext <- ["%%%", Base.encode64("short"), nil] do
      stub(KeyServiceHTTP, :post, fn url, _, _, _, _ ->
        response =
          if String.ends_with?(url, "/login"),
            do: %{"auth" => %{"client_token" => "token"}},
            else: %{"data" => %{"plaintext" => plaintext}}

        {:ok, JSON.encode!(response)}
      end)

      assert OpenBaoShareProvider.unwrap(share(@key), "aad") == {:error, :key_service_unavailable}
    end
  end

  test "configuration requires an HTTPS origin, explicit role/key and safe path segments" do
    assert :disabled = Environment.kura_volume_openbao(%{})
    assert {:ok, %{key_id: @key}} = Environment.kura_volume_openbao(@environment)

    for {name, value} <- [
          {"ADDRESS", "http://openbao.test"},
          {"ADDRESS", "https://user:password@openbao.test"},
          {"ADDRESS", "https://openbao.test/prefix"},
          {"ADDRESS", "https://openbao.test?redirect=yes"},
          {"ADDRESS", "https://openbao.test#fragment"},
          {"ROLE", ""},
          {"KEY_NAME", "../other"},
          {"TRANSIT_MOUNT", "transit/../../sys"},
          {"AUTH_MOUNT", "%2f"},
          {"DECRYPT_KEY_NAMES", "good,../other"},
          {"TOKEN_FILE", "relative"},
          {"CA_CERT_FILE", ""}
        ] do
      assert {:error, :invalid_openbao_configuration} =
               Environment.kura_volume_openbao(Map.put(@environment, "TUIST_KURA_VOLUME_OPENBAO_" <> name, value))
    end

    assert {:error, :invalid_openbao_configuration} =
             Environment.kura_volume_openbao(%{"TUIST_KURA_VOLUME_OPENBAO_CA_CERT_FILE" => "/ca.pem"})

    assert {:ok, config} =
             Environment.kura_volume_openbao(
               Map.merge(@environment, %{
                 "TUIST_KURA_VOLUME_OPENBAO_DECRYPT_KEY_NAMES" => "old-key",
                 "TUIST_KURA_VOLUME_OPENBAO_CA_CERT_FILE" => "/ca.pem"
               })
             )

    assert config.ca_cert_file == "/ca.pem"
    assert config.decrypt_keys[@address <> "/v1/transit/keys/old-key"] == "old-key"
  end

  test "rewrap preserves passphrases through root removal, outage and recovery", %{config: config} do
    account = AccountsFixtures.account_fixture()
    root = :crypto.strong_rand_bytes(32)
    stub(Environment, :kura_volume_openbao, fn -> :disabled end)
    stub(Environment, :kura_volume_root_keys, fn -> [{"legacy", root}] end)
    {:ok, key} = VolumeKeys.ensure_active_key(account)
    {:ok, passphrase} = VolumeKeys.volume_passphrase(account, key, "pvc-recovery")

    stub(Environment, :kura_volume_openbao, fn -> {:ok, config} end)
    service = fake_openbao(:crypto.strong_rand_bytes(32))
    stub(KeyServiceHTTP, :post, service)
    assert {:ok, %{processed: 1, done: true}} = Rotation.batch({"openbao", @key})
    wrapped = Repo.reload!(key)
    assert [%{"provider" => "openbao", "key_id" => @key}] = wrapped.shares
    stub(Environment, :kura_volume_root_keys, fn -> [] end)
    assert VolumeKeys.volume_passphrase(account, wrapped, "pvc-recovery") == {:ok, passphrase}

    stub(KeyServiceHTTP, :post, fn _, _, _, _, _ -> {:error, :key_service_unavailable} end)
    assert VolumeKeys.volume_passphrase(account, wrapped, "pvc-recovery") == {:error, :key_service_unavailable}
    assert {:error, :key_service_unavailable} = VolumeKeys.rewrap_key(key.id, {"openbao", @key})
    assert Repo.reload!(key).shares == wrapped.shares
    stub(KeyServiceHTTP, :post, service)
    assert VolumeKeys.volume_passphrase(account, Repo.reload!(key), "pvc-recovery") == {:ok, passphrase}

    # An old database record still needs its old root after a restore.
    assert {:error, :unknown_root_key} = VolumeKeys.volume_passphrase(account, key, "pvc-recovery")
    stub(Environment, :kura_volume_root_keys, fn -> [{"legacy", root}] end)
    assert VolumeKeys.volume_passphrase(account, key, "pvc-recovery") == {:ok, passphrase}
  end

  test "ciphertext cannot be moved across a tenant, version or share position" do
    stub(KeyServiceHTTP, :post, fake_openbao(:crypto.strong_rand_bytes(32)))
    {:ok, wrapped} = OpenBaoShareProvider.wrap(:crypto.strong_rand_bytes(32), "tenant|1|0")

    for aad <- ["other|1|0", "tenant|2|0", "tenant|1|1"] do
      assert OpenBaoShareProvider.unwrap(wrapped, aad) == {:error, :key_service_unavailable}
    end
  end

  test "a concurrent change cannot be overwritten by a completed rewrap", %{config: config} do
    account = AccountsFixtures.account_fixture()
    root = :crypto.strong_rand_bytes(32)
    stub(Environment, :kura_volume_openbao, fn -> :disabled end)
    stub(Environment, :kura_volume_root_keys, fn -> [{"legacy", root}] end)
    {:ok, key} = VolumeKeys.ensure_active_key(account)
    winner = Enum.map(key.shares, &Map.put(&1, "migration_marker", "concurrent-winner"))
    stub(Environment, :kura_volume_openbao, fn -> {:ok, config} end)
    service = fake_openbao(:crypto.strong_rand_bytes(32))

    stub(KeyServiceHTTP, :post, fn url, headers, type, body, ca ->
      if String.contains?(url, "/encrypt/") do
        Repo.update_all(from(k in TenantKey, where: k.id == ^key.id), set: [shares: winner])
      end

      service.(url, headers, type, body, ca)
    end)

    assert {:error, :concurrent_key_change} = VolumeKeys.rewrap_key(key.id, {"openbao", @key})
    assert Repo.reload!(key).shares == winner
  end

  defp share(key),
    do: %{"provider" => "openbao", "key_id" => key, "ciphertext" => "vault:v1:" <> Base.encode64("wrapped")}

  # A cryptographic stand-in; the disposable integration check uses real OpenBao.
  defp fake_openbao(root) do
    fn url, _, _, body, _ ->
      if String.ends_with?(url, "/login") do
        {:ok, JSON.encode!(%{"auth" => %{"client_token" => "workload-token"}})}
      else
        data = JSON.decode!(body)
        aad = Base.decode64!(data["associated_data"])
        root = :crypto.mac(:hmac, :sha256, root, List.last(String.split(url, "/")))

        transit_response(data, root, aad)
      end
    end
  end

  defp transit_response(%{"plaintext" => encoded}, root, aad) do
    nonce = :crypto.strong_rand_bytes(12)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, root, nonce, Base.decode64!(encoded), aad, 16, true)
    {:ok, JSON.encode!(%{"data" => %{"ciphertext" => "vault:v1:" <> Base.encode64(nonce <> ciphertext <> tag)}})}
  end

  defp transit_response(%{"ciphertext" => encoded}, root, aad) do
    <<nonce::binary-size(12), ciphertext::binary-size(32), tag::binary-size(16)>> =
      encoded |> String.replace_prefix("vault:v1:", "") |> Base.decode64!()

    case :crypto.crypto_one_time_aead(:aes_256_gcm, root, nonce, ciphertext, aad, tag, false) do
      :error -> {:error, :key_service_unavailable}
      plaintext -> {:ok, JSON.encode!(%{"data" => %{"plaintext" => Base.encode64(plaintext)}})}
    end
  end
end
