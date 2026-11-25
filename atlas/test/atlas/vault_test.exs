defmodule Atlas.VaultTest do
  use ExUnit.Case, async: true

  alias Atlas.Vault
  alias Cloak.Ciphers.AES.GCM

  @legacy Base.encode64(:binary.copy(<<1>>, 32))
  @k2 Base.encode64(:binary.copy(<<2>>, 32))
  @k3 Base.encode64(:binary.copy(<<3>>, 32))

  test "ENCRYPTION_KEY alone is the single AES.GCM.V1 cipher Atlas always had" do
    assert Vault.ciphers(Vault.keys!(key: @legacy)) == [
             default: {GCM, tag: "AES.GCM.V1", key: Base.decode64!(@legacy)}
           ]
  end

  test "values written under V1 stay readable after a ring is added, and V1 stays current" do
    stored = encrypt([key: @legacy], "secret")

    config = [key: @legacy, keys: "k2:#{@k2}"]
    assert [{"V1", _}, {"k2", _}] = Vault.keys!(config)
    assert decrypt(config, stored) == "secret"
    assert tag(encrypt(config, "new")) == "AES.GCM.V1"
  end

  test "encrypts with the chosen current key and still reads the others" do
    stored = encrypt([key: @legacy], "secret")
    config = [key: @legacy, keys: "k2:#{@k2},k3:#{@k3}", current_key: "k3"]

    assert tag(encrypt(config, "new")) == "AES.GCM.k3"
    assert decrypt(config, stored) == "secret"
    assert decrypt([keys: "k3:#{@k3}"], encrypt(config, "new")) == "new"
  end

  test "a ring alone encrypts with its first entry" do
    assert [{"k2", _}, {"k3", _}] = Vault.keys!(keys: "k2:#{@k2},k3:#{@k3}")
  end

  test "refuses malformed keys without echoing them" do
    short = Base.encode64(:binary.copy(<<4>>, 16))

    for {config, message} <- [
          {[keys: "k2:#{short}"], ~r/entry 1 must be/},
          {[keys: "k2:#{@k2},bad#{@k3}"], ~r/entry 2 must be/},
          {[keys: "V1:#{@k2}"], ~r/other than V1/},
          {[keys: "k2:#{@k2},k2:#{@k3}"], ~r/no id twice/},
          {[key: short], ~r/ENCRYPTION_KEY must be base64/},
          {[key: "not base64!"], ~r/ENCRYPTION_KEY must be base64/},
          {[key: @legacy, current_key: "k9"], ~r/ENCRYPTION_CURRENT_KEY is "k9"/},
          {[], ~r/no key/}
        ] do
      error = assert_raise RuntimeError, message, fn -> Vault.keys!(config) end

      for secret <- [@legacy, @k2, @k3, short, "not base64!"] do
        refute error.message =~ secret
      end
    end
  end

  test "refuses to boot without every key ENCRYPTION_KEY_IDS lists" do
    assert [_, _] = Vault.keys!(key: @legacy, keys: "k2:#{@k2}", key_ids: "V1, k2")

    assert_raise RuntimeError, ~r/ENCRYPTION_KEY_IDS lists k2, which this node has no key for/, fn ->
      Vault.keys!(key: @legacy, key_ids: "V1,k2")
    end
  end

  defp encrypt(config, plaintext), do: Cloak.Vault.encrypt!(cipher_config(config), plaintext)
  defp decrypt(config, ciphertext), do: Cloak.Vault.decrypt!(cipher_config(config), ciphertext)
  defp cipher_config(config), do: [ciphers: Vault.ciphers(Vault.keys!(config))]

  defp tag(<<1, length, tag::binary-size(length), _rest::binary>>), do: tag
end
