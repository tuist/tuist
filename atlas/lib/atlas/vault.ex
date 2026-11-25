defmodule Atlas.Vault do
  @moduledoc """
  Encrypts the `Atlas.Encrypted.Binary` fields.

  It holds one AES-GCM cipher per key from `keys!/1`: new values are encrypted
  with the current key, and each value is decrypted with the key its tag
  (`AES.GCM.<id>`) names, so values under older keys stay readable until
  `Atlas.Release.reencrypt_vault/2` moves them to the current key.

  - `ENCRYPTION_KEY`: the original single key, base64 of 32 bytes, with id
    `V1`. Every value written before the key ring is tagged `AES.GCM.V1`.
  - `ENCRYPTION_KEYS`: comma-separated `id:base64` entries of 32 bytes each.
  - `ENCRYPTION_CURRENT_KEY`: the id to encrypt with; `V1` by default, or the
    first `ENCRYPTION_KEYS` entry once `ENCRYPTION_KEY` is gone.
  - `ENCRYPTION_KEY_IDS`: comma-separated ids every node must hold. A node
    missing one refuses to boot.

  With only `ENCRYPTION_KEY` set, this is the single `AES.GCM.V1` cipher
  Atlas always had.

  ## Rotating the key

  Every replica has to read a key before any replica writes with it, so a
  rotation takes three deploys. In managed production, `ENCRYPTION_KEYS` comes
  from 1Password through the `atlas-app` ExternalSecret, which refreshes
  hourly without restarting pods, while `ENCRYPTION_CURRENT_KEY` and
  `ENCRYPTION_KEY_IDS` are plain Helm `env` values, so changing them rolls
  every pod.

  1. Generate a key (`openssl rand -base64 32`), add `<id>:<key>` to
     `ENCRYPTION_KEYS` (comma-separated after any existing entries), and wait
     for the Secret to sync. Set `ENCRYPTION_KEY_IDS` to the old and new ids
     (`V1,<id>` the first time) and pin `ENCRYPTION_CURRENT_KEY` to the old
     id, then deploy. A pod whose Secret lacks a listed key refuses to boot
     until it has it, so after this deploy every running pod reads the new key.
  2. Set `ENCRYPTION_CURRENT_KEY` to the new id and deploy. New values are
     now written under it.
  3. Run `bin/atlas eval 'Atlas.Release.reencrypt_vault("<id>")'` until it
     passes. Then remove the old key (`ENCRYPTION_KEY` for `V1`, or its
     `ENCRYPTION_KEYS` entry) and its id from `ENCRYPTION_KEY_IDS`, and deploy.

  When the old key is compromised, steps 1 and 2 can ship together: during
  that rollout, pods still on the old configuration fail to read values the
  new ones write.

  Rolling back to an image without the key ring after step 2 leaves values
  written under the new key unreadable. First set `ENCRYPTION_CURRENT_KEY`
  back to `V1`, deploy, and run `Atlas.Release.reencrypt_vault("V1")`.
  """
  use Cloak.Vault, otp_app: :atlas

  alias Cloak.Ciphers.AES.GCM

  @legacy_key_id "V1"
  @key_id_regex ~r/\A[A-Za-z0-9_.-]{1,32}\z/

  @impl GenServer
  def init(config) do
    {:ok, Keyword.put(config, :ciphers, config |> keys!() |> ciphers())}
  end

  @doc """
  The `{id, 32-byte key}` pairs the vault holds, the current key first, from
  the `:key`, `:keys`, `:current_key` and `:key_ids` options, which
  `config/runtime.exs` reads from `ENCRYPTION_KEY`, `ENCRYPTION_KEYS`,
  `ENCRYPTION_CURRENT_KEY` and `ENCRYPTION_KEY_IDS`. Raises, without echoing
  key material, when they are malformed or a required id is missing.
  """
  def keys!(config) do
    keys = ring(config[:keys]) ++ legacy(config[:key])

    if keys == [] do
      raise "Set ENCRYPTION_KEY or ENCRYPTION_KEYS: Atlas has no key to encrypt stored secrets with"
    end

    keys = current_first(keys, blank_to_nil(config[:current_key]))
    require_key_ids!(keys, blank_to_nil(config[:key_ids]))
    keys
  end

  @doc """
  One cipher per key, labeled `:default` for the first, the current key.
  """
  def ciphers(keys) do
    keys
    |> Enum.with_index()
    |> Enum.map(fn {{id, key}, index} ->
      label = if index == 0, do: :default, else: :"retired_#{index}"
      {label, {GCM, tag: "AES.GCM.#{id}", key: key}}
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

  defp legacy(value) do
    case blank_to_nil(value) do
      nil ->
        []

      value ->
        case Base.decode64(value) do
          {:ok, <<_::binary-size(32)>> = key} -> [{@legacy_key_id, key}]
          # Never echo the value: it is key material.
          _ -> raise "ENCRYPTION_KEY must be base64 decoding to 32 bytes"
        end
    end
  end

  defp ring(value) do
    case blank_to_nil(value) do
      nil -> []
      value -> parse_ring!(value)
    end
  end

  defp parse_ring!(value) do
    entries =
      value
      |> String.split(",", trim: true)
      |> Enum.with_index(1)
      |> Enum.map(fn {entry, position} ->
        with [id, encoded] <- entry |> String.trim() |> String.split(":", parts: 2),
             true <- Regex.match?(@key_id_regex, id) and id != @legacy_key_id,
             {:ok, <<_::binary-size(32)>> = key} <- Base.decode64(String.trim(encoded)) do
          {id, key}
        else
          # Never echo the entry: it holds key material.
          _ ->
            raise "ENCRYPTION_KEYS entry #{position} must be `id:base64` with an id of letters, digits, " <>
                    "`_`, `.` or `-` other than #{@legacy_key_id}, and a key decoding to 32 bytes"
        end
      end)

    ids = Enum.map(entries, &elem(&1, 0))

    if entries == [] or length(Enum.uniq(ids)) != length(ids) do
      raise "ENCRYPTION_KEYS must list at least one key and no id twice"
    end

    entries
  end

  # V1 stays current until another key is chosen explicitly, so adding a ring
  # never changes what new values are encrypted with.
  defp current_first(keys, nil) do
    case List.keyfind(keys, @legacy_key_id, 0) do
      nil -> keys
      legacy -> [legacy | List.delete(keys, legacy)]
    end
  end

  defp current_first(keys, current_id) do
    case List.keyfind(keys, current_id, 0) do
      nil ->
        raise "ENCRYPTION_CURRENT_KEY is #{inspect(current_id)}, which is not a configured encryption key id"

      current ->
        [current | List.delete(keys, current)]
    end
  end

  # A pod started before its Secret has a new key refuses to boot, and picks
  # the key up when it restarts, instead of serving without being able to read
  # what other pods will write with it.
  defp require_key_ids!(_keys, nil), do: :ok

  defp require_key_ids!(keys, ids) do
    held = Enum.map(keys, &elem(&1, 0))
    missing = ids |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 in held))

    if missing != [] do
      raise "ENCRYPTION_KEY_IDS lists #{Enum.join(missing, ", ")}, which this node has no key for; " <>
              "wait for the application Secret to sync and restart"
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
