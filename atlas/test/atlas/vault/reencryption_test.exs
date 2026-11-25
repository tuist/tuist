defmodule Atlas.Vault.ReencryptionTest do
  use Atlas.DataCase, async: true
  use Mimic

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias Atlas.MCP.ServerConfiguration
  alias Atlas.Release
  alias Atlas.Vault
  alias Atlas.Vault.Reencryption
  alias Cloak.Ciphers.AES.GCM

  setup do
    # Each test swaps the vault's keys for its own process only, through
    # Mimic, so the application's vault and other tests are untouched.
    legacy = :crypto.strong_rand_bytes(32)
    use_keys([{"V1", legacy}])
    %{legacy: legacy, new: :crypto.strong_rand_bytes(32)}
  end

  test "finds the encrypted fields from the schemas, with their tables' primary keys" do
    tables = Map.new(Reencryption.tables(), &{&1.table, &1})

    assert %{primary_key: ["id"], columns: ["bearer_token"]} = tables["mcp_server_configurations"]
    assert tables["licenses"].columns == ["key", "signing_key"]
    assert %{columns: ["bot_token"]} = tables["slack_installations"]
  end

  test "moves every value from V1 to the new key, and a rerun finds nothing left", %{legacy: legacy, new: new} do
    secrets = for n <- 1..5, do: "token-#{n}"
    servers = Enum.map(secrets, &insert_server!/1)
    unset = insert_server!(nil)

    assert Enum.all?(servers, &(tag(&1) == "AES.GCM.V1"))

    # Without V1 the stored values cannot be read: the control that makes the
    # read after re-encrypting meaningful.
    use_keys([{"k2", new}])
    assert_raise ArgumentError, fn -> Repo.get!(ServerConfiguration, hd(servers).id) end

    use_keys([{"k2", new}, {"V1", legacy}])
    counts = reencrypt_vault("k2", batch_size: 2)

    assert counts["mcp_server_configurations.bearer_token"] == %{reencrypted: 5, changed: 0, failed: 0}
    assert Enum.all?(servers, &(tag(&1) == "AES.GCM.k2"))
    assert raw(unset) == nil

    use_keys([{"k2", new}])
    assert Enum.map(servers, &Repo.get!(ServerConfiguration, &1.id).bearer_token) == secrets

    rerun = reencrypt_vault("k2")
    assert rerun["mcp_server_configurations.bearer_token"] == %{reencrypted: 0, changed: 0, failed: 0}
  end

  test "refuses to run unless the node already encrypts with the given key", %{legacy: legacy, new: new} do
    use_keys([{"V1", legacy}, {"k2", new}])

    assert_raise RuntimeError, ~r/encrypts with AES.GCM.V1, not AES.GCM.k2/, fn ->
      Release.reencrypt_vault("k2")
    end
  end

  test "re-encrypts what it can and fails the run, without logging keys, on undecryptable values", %{
    legacy: legacy,
    new: new
  } do
    readable = insert_server!("readable")
    unknown_tag = insert_server!("x")
    wrong_key = insert_server!("y")

    # A tag no configured key has, and V1's tag under another key, which Cloak
    # reports as `{:ok, :error}`.
    {:ok, foreign} = GCM.encrypt("foreign", tag: "AES.GCM.gone", key: :crypto.strong_rand_bytes(32))
    {:ok, forged} = GCM.encrypt("forged", tag: "AES.GCM.V1", key: :crypto.strong_rand_bytes(32))
    set_raw!(unknown_tag, foreign)
    set_raw!(wrong_key, forged)

    use_keys([{"k2", new}, {"V1", legacy}])

    log =
      capture_log(fn ->
        error = assert_raise RuntimeError, fn -> reencrypt_vault("k2") end
        assert error.message =~ "mcp_server_configurations.bearer_token (2)"
      end)

    refute log =~ inspect(new)
    refute log =~ inspect(legacy)
    assert tag(readable) == "AES.GCM.k2"
    assert raw(unknown_tag) == foreign
    assert raw(wrong_key) == forged
  end

  defp reencrypt_vault(key_id, opts \\ []) do
    {counts, _output} = with_io(fn -> Release.reencrypt_vault(key_id, opts) end)
    counts
  end

  defp insert_server!(token) do
    Repo.insert!(%ServerConfiguration{
      name: "reencryption-#{System.unique_integer([:positive])}",
      url: "https://mcp.example.com",
      auth_type: "bearer",
      bearer_token: token
    })
  end

  defp raw(server) do
    %{rows: [[value]]} =
      Repo.query!("SELECT bearer_token FROM mcp_server_configurations WHERE id = $1", [Ecto.UUID.dump!(server.id)])

    value
  end

  defp set_raw!(server, value) do
    Repo.query!("UPDATE mcp_server_configurations SET bearer_token = $1 WHERE id = $2", [
      value,
      Ecto.UUID.dump!(server.id)
    ])
  end

  defp tag(server) do
    <<1, length, tag::binary-size(length), _rest::binary>> = raw(server)
    tag
  end

  defp use_keys(keys) do
    config = [ciphers: Vault.ciphers(keys)]
    [{_label, cipher} | _] = config[:ciphers]

    stub(Vault, :encrypt, &Cloak.Vault.encrypt(config, &1))
    stub(Vault, :encrypt!, &Cloak.Vault.encrypt!(config, &1))
    stub(Vault, :decrypt, &Cloak.Vault.decrypt(config, &1))
    stub(Vault, :decrypt!, &Cloak.Vault.decrypt!(config, &1))
    stub(Vault, :current_cipher, fn -> cipher end)
  end
end
