defmodule Tuist.Vault do
  @moduledoc """
  Encrypts the `Tuist.Vault.Binary` fields and other stored secrets.

  It holds one AES-GCM cipher per key from `Tuist.Environment.encryption_keys/0`:
  new values are encrypted with the first, the current key, and each value is
  decrypted with the key its tag names, so values under retired keys stay
  readable until `Tuist.Release.reencrypt_vault/2` moves them to the current
  key.

  ## Rotating the key

  Every node has to hold a key before any node writes with it, so a rotation
  takes three deploys (Helm values under `server.config.encryptionKeys`):

  1. Generate a key (`openssl rand -base64 32`) and add `<id>:<key>` to the
     1Password field `SECRET_KEYS/encryption_keys` (`enabled: true` the first
     time). Force a sync of the server config ExternalSecret. Add the id to
     `keyIds` and pin `currentKeyId` to the key in use (`V1` for the
     original single key), then deploy. Changing `keyIds` rolls every pod,
     and a pod whose synced Secret lacks a listed key refuses to boot until
     it has it, so after this deploy every running pod reads the new key.
  2. Set `currentKeyId` to the new id and deploy. Helm refuses an id that
     `keyIds` does not list.
  3. Run `bin/tuist eval 'Tuist.Release.reencrypt_vault("<id>")'` until it
     passes, wait for the Oban jobs queued before step 2 to run, then remove
     the old key from the 1Password field and `keyIds` (`legacyKey: false`
     for `V1`) and deploy.

  When the old key is compromised, steps 1 and 2 can ship together: during
  that rollout, nodes still on the old configuration fail to read values the
  new ones write.
  """
  use Cloak.Vault, otp_app: :tuist

  @impl GenServer
  def init(config) do
    keys =
      case Keyword.fetch!(config, :keys) do
        {module, function, args} -> apply(module, function, args)
        keys -> keys
      end

    {:ok, Keyword.put(config, :ciphers, ciphers(keys))}
  end

  defp ciphers(keys) do
    keys
    |> Enum.with_index()
    |> Enum.map(fn {{id, key}, index} ->
      label = if index == 0, do: :default, else: :"retired_#{index}"
      {label, {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.#{id}", key: key}}
    end)
  end

  @doc """
  The cipher new values are encrypted with, as `{module, opts}`.
  """
  def current_cipher do
    {:ok, config} = Cloak.Vault.read_config(@table_name)
    [{_label, cipher} | _retired] = Keyword.fetch!(config, :ciphers)
    cipher
  end
end
