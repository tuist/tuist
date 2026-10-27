defmodule Tuist.Kura.VolumeKeysTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Kura.VolumeKeys
  alias Tuist.Kura.VolumeKeys.HKDF
  alias Tuist.Kura.VolumeKeys.Rotation
  alias Tuist.Kura.VolumeKeys.TenantKey
  alias Tuist.Kura.VolumeKeys.TuistRootShareProvider
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    stub(Environment, :kura_volume_kms, fn -> :disabled end)
    root_key = :crypto.strong_rand_bytes(32)
    stub(Environment, :kura_volume_root_keys, fn -> [{"root-a", root_key}] end)
    %{account: AccountsFixtures.account_fixture(), root_key: root_key}
  end

  describe "root rewrap and recovery" do
    test "rewrap preserves passphrases, survives removal of the old root and retries", %{
      account: account,
      root_key: old_root
    } do
      {:ok, key} = VolumeKeys.ensure_active_key(account)
      {:ok, before} = VolumeKeys.volume_passphrase(account, key, "pvc-a")
      new_root = :crypto.strong_rand_bytes(32)
      stub(Environment, :kura_volume_root_keys, fn -> [{"root-b", new_root}, {"root-a", old_root}] end)

      assert {:ok, %{processed: 1, done: true}} = Rotation.batch({"tuist_root", "root-b"})
      assert [%{key_id: "root-b", shares: 1}] = Rotation.inventory()
      stub(Environment, :kura_volume_root_keys, fn -> [{"root-b", new_root}] end)
      assert VolumeKeys.volume_passphrase(account, Repo.reload!(key), "pvc-a") == {:ok, before}
      assert :ok = VolumeKeys.rewrap_key(key.id, {"tuist_root", "root-b"})
      assert VolumeKeys.volume_passphrase(account, Repo.reload!(key), "pvc-a") == {:ok, before}

      # Restoring a pre-migration DB backup still requires the old root.
      assert {:error, :unknown_root_key} = VolumeKeys.volume_passphrase(account, key, "pvc-a")
      stub(Environment, :kura_volume_root_keys, fn -> [{"root-a", old_root}] end)
      assert VolumeKeys.volume_passphrase(account, key, "pvc-a") == {:ok, before}
    end

    test "missing source key leaves the stored row unchanged", %{account: account} do
      {:ok, key} = VolumeKeys.ensure_active_key(account)
      stub(Environment, :kura_volume_root_keys, fn -> [{"root-b", :crypto.strong_rand_bytes(32)}] end)
      assert {:error, :unknown_root_key} = VolumeKeys.rewrap_key(key.id, {"tuist_root", "root-b"})
      assert Repo.reload!(key).shares == key.shares
    end

    test "pins the intended target and includes retired versions", %{account: account, root_key: old_root} do
      {:ok, key} = VolumeKeys.ensure_active_key(account)
      Repo.update_all(from(k in TenantKey, where: k.id == ^key.id), set: [state: :retired])
      {:ok, active} = VolumeKeys.ensure_active_key(account)
      new_root = :crypto.strong_rand_bytes(32)
      stub(Environment, :kura_volume_root_keys, fn -> [{"root-b", new_root}, {"root-a", old_root}] end)
      assert {:error, :wrapping_target_changed} = Rotation.batch({"tuist_root", "wrong"})
      assert {:error, :invalid_limit} = Rotation.batch({"tuist_root", "root-b"}, limit: 0)
      assert {:ok, %{processed: 1, after_id: cursor, done: false}} = Rotation.batch({"tuist_root", "root-b"}, limit: 1)
      assert {:ok, %{processed: 1}} = Rotation.batch({"tuist_root", "root-b"}, limit: 1, after_id: cursor)
      assert Enum.all?(Rotation.inventory(), &(&1.key_id == "root-b"))
      assert Repo.reload!(key).state == :retired
      assert Repo.reload!(active).state == :active
    end

    test "invalid KMS configuration never falls back to an exportable root" do
      stub(Environment, :kura_volume_kms, fn -> {:error, :invalid_kms_configuration} end)
      refute VolumeKeys.available?()
      assert {:error, :invalid_kms_configuration} = VolumeKeys.wrapping_target()
    end
  end

  describe "TuistRootShareProvider" do
    test "unwraps what it wrapped" do
      plaintext = :crypto.strong_rand_bytes(32)

      assert {:ok, %{"provider" => "tuist_root", "key_id" => "root-a", "ciphertext" => ciphertext} = share} =
               TuistRootShareProvider.wrap(plaintext, "aad")

      assert byte_size(Base.decode64!(ciphertext)) == 12 + 32 + 16
      assert TuistRootShareProvider.unwrap(share, "aad") == {:ok, plaintext}
    end

    test "unwraps with an old root and wraps with the new one", %{root_key: root_key} do
      plaintext = :crypto.strong_rand_bytes(32)
      {:ok, share} = TuistRootShareProvider.wrap(plaintext, "aad")

      stub(Environment, :kura_volume_root_keys, fn ->
        [{"root-b", :crypto.strong_rand_bytes(32)}, {"root-a", root_key}]
      end)

      assert TuistRootShareProvider.unwrap(share, "aad") == {:ok, plaintext}
      assert {:ok, %{"key_id" => "root-b"}} = TuistRootShareProvider.wrap(plaintext, "aad")
    end

    test "refuses a share whose root key is gone, or whose AAD differs" do
      {:ok, share} = TuistRootShareProvider.wrap(:crypto.strong_rand_bytes(32), "aad")

      assert TuistRootShareProvider.unwrap(share, "other aad") == {:error, :decryption_failed}

      stub(Environment, :kura_volume_root_keys, fn -> [{"root-b", :crypto.strong_rand_bytes(32)}] end)
      assert TuistRootShareProvider.unwrap(share, "aad") == {:error, :unknown_root_key}
    end

    test "wraps nothing without root keys" do
      stub(Environment, :kura_volume_root_keys, fn -> [] end)
      assert TuistRootShareProvider.wrap(:crypto.strong_rand_bytes(32), "aad") == {:error, :root_keys_unavailable}
    end
  end

  describe "ensure_active_key/1" do
    test "creates version 1 once and returns it afterwards", %{account: account} do
      result = VolumeKeys.ensure_active_key(account)
      assert {:ok, %TenantKey{version: 1, state: :active, shares: [share]} = key} = result
      assert %{"provider" => "tuist_root", "key_id" => "root-a"} = share

      assert {:ok, %TenantKey{id: id}} = VolumeKeys.ensure_active_key(account)
      assert id == key.id
      assert Repo.aggregate(from(k in TenantKey, where: k.account_id == ^account.id), :count) == 1
    end

    test "returns the winner when another request created the key first", %{account: account} do
      {:ok, winner} = VolumeKeys.ensure_active_key(account)

      assert {:error, %Ecto.Changeset{}} =
               %{account_id: account.id, version: 2, shares: winner.shares, state: :active}
               |> TenantKey.create_changeset()
               |> Repo.insert()

      assert {:ok, %TenantKey{id: id}} = VolumeKeys.ensure_active_key(account)
      assert id == winner.id
    end

    test "deleting the account deletes its keys", %{account: account} do
      {:ok, key} = VolumeKeys.ensure_active_key(account)
      Repo.delete!(account)
      assert Repo.get(TenantKey, key.id) == nil
    end
  end

  describe "volume_passphrase/3" do
    test "is a deterministic 32-byte secret per volume", %{account: account} do
      {:ok, key} = VolumeKeys.ensure_active_key(account)

      assert {:ok, passphrase} = VolumeKeys.volume_passphrase(account, key, "pvc-a")
      assert byte_size(passphrase) == 32
      assert VolumeKeys.volume_passphrase(account, Repo.reload!(key), "pvc-a") == {:ok, passphrase}
      assert {:ok, other} = VolumeKeys.volume_passphrase(account, key, "pvc-b")
      assert other != passphrase
    end

    test "is HKDF over the unwrapped shares, bound to the tenant", %{account: account} do
      {:ok, %TenantKey{shares: [share]} = key} = VolumeKeys.ensure_active_key(account)
      tenant_id = account.kura_tenant_id
      {:ok, secret} = TuistRootShareProvider.unwrap(share, "kura-tenant-key/v1|#{tenant_id}|1|0")

      assert VolumeKeys.volume_passphrase(account, key, "pvc-a") ==
               {:ok, HKDF.derive(secret, "kura-volume-key/v1", tenant_id <> <<0>> <> "pvc-a", 32)}
    end

    test "refuses shares moved to another tenant", %{account: account} do
      {:ok, key} = VolumeKeys.ensure_active_key(account)
      other = AccountsFixtures.account_fixture()

      assert VolumeKeys.volume_passphrase(other, %{key | account_id: other.id}, "pvc-a") ==
               {:error, :decryption_failed}
    end
  end

  describe "seal/3" do
    test "seals the passphrase to the client's X25519 key" do
      {client_public, client_private} = :crypto.generate_key(:ecdh, :x25519)
      passphrase = :crypto.strong_rand_bytes(32)

      assert {:ok, %{ephemeral_public_key: server_public, nonce: nonce, ciphertext: sealed}} =
               VolumeKeys.seal(passphrase, "pvc-a", client_public)

      assert byte_size(server_public) == 32
      assert byte_size(nonce) == 12
      assert byte_size(sealed) == 32 + 16
      assert open(sealed, nonce, server_public, client_public, client_private, "pvc-a") == passphrase
      assert open(sealed, nonce, server_public, client_public, client_private, "pvc-b") == :error
    end

    test "rejects a low-order public key" do
      assert VolumeKeys.seal(:crypto.strong_rand_bytes(32), "pvc-a", <<0::256>>) == {:error, :invalid_public_key}
    end
  end

  # The client side of the transport, written out from the documented format.
  def open(sealed, nonce, server_public, client_public, client_private, volume_id) do
    shared = :crypto.compute_key(:ecdh, server_public, client_private, :x25519)
    key = HKDF.derive(shared, server_public <> client_public, "kura-volume-key-transport/v1", 32)
    ciphertext = binary_part(sealed, 0, byte_size(sealed) - 16)
    tag = binary_part(sealed, byte_size(sealed), -16)
    :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, ciphertext, volume_id, tag, false)
  end
end
