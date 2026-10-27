defmodule Tuist.Kura.VolumeKeys do
  @moduledoc """
  Keys for Kura data volumes encrypted at rest.

  Every Kura replica's data volume is a LUKS2 container built by the
  `kura-volumes.tuist.dev` CSI driver, which asks this module for the
  volume's passphrase whenever the volume is staged on a node.

  ## Composite-share model

  An account has a versioned tenant key (`Tuist.Kura.VolumeKeys.TenantKey`).
  A version is a list of shares, each 32 random bytes wrapped by a
  `Tuist.Kura.VolumeKeys.ShareProvider`. A volume passphrase is
  HKDF-SHA256 over the concatenation of every unwrapped share, in order,
  with salt `"kura-volume-key/v1"` and info `tenant_id <> <<0>> <> volume_id`,
  so each volume has its own passphrase and producing any of them requires
  every share of the version.

  Each version currently has one Tuist-managed share, wrapped either by the
  legacy `tuist_root` provider or the configured `openbao` provider. Rewrapping
  changes only its envelope, preserving plaintext and volume passphrases.
  Future organization-managed KMS shares require a new key version. Revocation
  prevents future unwraps; it does not close an already-open LUKS mapping.
  Adding a provider is a new `ShareProvider` and an entry in the provider
  table here; the stored shares carry their provider, so the schema does not
  change.

  Each share is bound to its tenant, version, and position through the AAD
  `"kura-tenant-key/v1|" <> tenant_id <> "|" <> version <> "|" <> index`.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura.Identity
  alias Tuist.Kura.Server
  alias Tuist.Kura.VolumeKeys.HKDF
  alias Tuist.Kura.VolumeKeys.OpenBaoShareProvider
  alias Tuist.Kura.VolumeKeys.TenantKey
  alias Tuist.Kura.VolumeKeys.TuistRootShareProvider
  alias Tuist.Repo

  require Logger

  @providers %{"tuist_root" => TuistRootShareProvider, "openbao" => OpenBaoShareProvider}
  @share_bytes 32
  @passphrase_bytes 32
  @tenant_key_aad_prefix "kura-tenant-key/v1|"
  @volume_key_salt "kura-volume-key/v1"
  @transport_info "kura-volume-key-transport/v1"
  @transport_nonce_bytes 12
  @transport_tag_bytes 16
  @x25519_public_key_bytes 32

  @driver "kura-volumes.tuist.dev"
  @audience "kura-volume-keys.tuist.dev"
  @node_topology_key "topology.kura-volumes.tuist.dev/node"
  @node_name_extra "authentication.kubernetes.io/node-name"
  @kura_namespace "kura"
  @instance_label "app.kubernetes.io/instance"
  @kubernetes_timeout_ms 5_000
  @volume_id_format ~r/\A[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?\z/

  def available?, do: match?({:ok, _, _}, wrapping_target())

  @doc "Returns the configured provider and pinned wrapping key identifier, never key material."
  def wrapping_target do
    case Environment.kura_volume_openbao() do
      {:ok, %{key_id: key_id}} ->
        {:ok, "openbao", key_id}

      :disabled ->
        case Environment.kura_volume_root_keys() do
          [{key_id, _} | _] -> {:ok, "tuist_root", key_id}
          [] -> {:error, :root_keys_unavailable}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Rewraps one persisted key's Tuist-managed shares without changing plaintext,
  version, order or volume passphrases. `target` pins the operator's intended
  destination as `{provider, key_id}`. Remote work runs outside a DB transaction;
  the final compare-and-swap refuses concurrent changes. Safe to retry after a
  crash. Active AND retired versions must be processed before retiring a root.
  """
  def rewrap_key(id, {provider, key_id} = target) do
    with {:ok, ^provider, ^key_id} <- wrapping_target(),
         %TenantKey{} = key <- Repo.get(TenantKey, id),
         %Account{} = account <- Repo.get(Account, key.account_id),
         {:ok, shares} <- rewrap_shares(Identity.tenant_id(account), key, target) do
      {count, _} =
        Repo.update_all(from(k in TenantKey, where: k.id == ^key.id and k.shares == ^key.shares),
          set: [shares: shares, updated_at: DateTime.utc_now(:second)]
        )

      if count == 1, do: :ok, else: {:error, :concurrent_key_change}
    else
      nil -> {:error, :key_not_found}
      {:error, _} = error -> error
      _ -> {:error, :wrapping_target_changed}
    end
  end

  defp rewrap_shares(tenant_id, %TenantKey{version: version, shares: shares}, {name, key_id}) do
    target = Map.fetch!(@providers, name)

    shares
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {share, index}, {:ok, result} ->
      aad = share_aad(tenant_id, version, index)

      with {:ok, source} <- share_provider(share),
           {:ok, <<_::256>> = plaintext} <- source.unwrap(share, aad),
           {:ok, %{"provider" => ^name, "key_id" => ^key_id} = wrapped} <- target.wrap(plaintext, aad),
           {:ok, ^plaintext} <- target.unwrap(wrapped, aad) do
        {:cont, {:ok, result ++ [wrapped]}}
      else
        {:error, _} = error -> {:halt, error}
        _ -> {:halt, {:error, :rewrap_verification_failed}}
      end
    end)
  end

  @doc """
  Issues the passphrase of `volume_id`, sealed to `client_public_key`, to the
  CSI node plugin presenting `token`.

  The caller must be the configured node plugin ServiceAccount, its token must
  be bound to a node, and the PersistentVolume must be a `kura-volumes`
  volume pinned to that node whose claim is a live Kura replica's. The
  account is the one whose Kura instance owns the claim.
  """
  def issue(token, volume_id, client_public_key, opts \\ []) do
    with :ok <- validate_volume_id(volume_id),
         :ok <- validate_public_key(client_public_key),
         :ok <- ensure_available(),
         {:ok, node_name} <- authenticate(token),
         {:ok, claim_ref} <- authorize_volume(volume_id, node_name),
         {:ok, account} <- claim_account(claim_ref, volume_id),
         {:ok, tenant_key} <- tenant_key(account, Keyword.get(opts, :key_version)),
         {:ok, passphrase} <- volume_passphrase(account, tenant_key, volume_id),
         {:ok, sealed} <- seal(passphrase, volume_id, client_public_key) do
      Logger.info(
        "[Kura.VolumeKeys] issued key version #{tenant_key.version} of account #{account.id} for volume #{volume_id} on node #{node_name}"
      )

      {:ok, Map.put(sealed, :key_version, tenant_key.version)}
    end
  end

  @doc """
  Returns the account's active tenant key, creating version 1 when the account
  has none. Concurrent first calls converge on whichever insert won.
  """
  def ensure_active_key(%Account{} = account) do
    case active_key(account) do
      %TenantKey{} = key -> {:ok, key}
      nil -> create_active_key(account)
    end
  end

  def active_key(%Account{id: account_id}) do
    Repo.one(from(k in TenantKey, where: k.account_id == ^account_id and k.state == :active))
  end

  def key_version(%Account{id: account_id}, version) when is_integer(version) do
    Repo.one(from(k in TenantKey, where: k.account_id == ^account_id and k.version == ^version))
  end

  @doc """
  The 32-byte passphrase of `volume_id` under `tenant_key`.
  """
  def volume_passphrase(%Account{id: account_id} = account, %TenantKey{account_id: account_id} = tenant_key, volume_id)
      when is_binary(volume_id) do
    tenant_id = Identity.tenant_id(account)

    with {:ok, shares} <- unwrap_shares(tenant_id, tenant_key) do
      {:ok,
       HKDF.derive(IO.iodata_to_binary(shares), @volume_key_salt, tenant_id <> <<0>> <> volume_id, @passphrase_bytes)}
    end
  end

  @doc """
  Seals `passphrase` to the holder of the X25519 private key behind
  `client_public_key`. See `TuistWeb.Internal.KuraVolumeKeysController` for
  the format.
  """
  def seal(passphrase, volume_id, client_public_key) do
    {server_public_key, server_private_key} = :crypto.generate_key(:ecdh, :x25519)

    with {:ok, sealing_key} <- transport_key(client_public_key, server_private_key, server_public_key) do
      nonce = :crypto.strong_rand_bytes(@transport_nonce_bytes)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(
          :aes_256_gcm,
          sealing_key,
          nonce,
          passphrase,
          volume_id,
          @transport_tag_bytes,
          true
        )

      {:ok, %{ephemeral_public_key: server_public_key, nonce: nonce, ciphertext: ciphertext <> tag}}
    end
  end

  # OpenSSL refuses to derive from a low-order point, whose shared secret would
  # be all zeros; both outcomes are rejected.
  defp transport_key(client_public_key, server_private_key, server_public_key) do
    case :crypto.compute_key(:ecdh, client_public_key, server_private_key, :x25519) do
      <<0::256>> -> {:error, :invalid_public_key}
      shared -> {:ok, HKDF.derive(shared, server_public_key <> client_public_key, @transport_info, 32)}
    end
  rescue
    ErlangError -> {:error, :invalid_public_key}
  end

  defp create_active_key(account) do
    tenant_id = Identity.tenant_id(account)
    version = next_version(account)

    with {:ok, shares} <- wrap_shares(tenant_id, version) do
      %{account_id: account.id, version: version, shares: shares, state: :active}
      |> TenantKey.create_changeset()
      |> Repo.insert()
      |> case do
        {:ok, key} ->
          {:ok, key}

        {:error, %Ecto.Changeset{} = changeset} ->
          case active_key(account) do
            %TenantKey{} = key -> {:ok, key}
            nil -> {:error, changeset}
          end
      end
    end
  end

  defp next_version(%Account{id: account_id}) do
    (Repo.one(from(k in TenantKey, where: k.account_id == ^account_id, select: max(k.version))) || 0) + 1
  end

  defp wrap_shares(tenant_id, version) do
    with {:ok, provider, _key_id} <- wrapping_target() do
      wrap_shares(tenant_id, version, [Map.fetch!(@providers, provider)])
    end
  end

  defp wrap_shares(tenant_id, version, providers) do
    providers
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {provider, index}, {:ok, shares} ->
      plaintext = :crypto.strong_rand_bytes(@share_bytes)

      case provider.wrap(plaintext, share_aad(tenant_id, version, index)) do
        {:ok, share} -> {:cont, {:ok, shares ++ [share]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp unwrap_shares(tenant_id, %TenantKey{version: version, shares: shares}) do
    shares
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {share, index}, {:ok, plaintexts} ->
      with {:ok, provider} <- share_provider(share),
           {:ok, plaintext} <- provider.unwrap(share, share_aad(tenant_id, version, index)) do
        {:cont, {:ok, plaintexts ++ [plaintext]}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp share_provider(%{"provider" => name}) do
    case Map.fetch(@providers, name) do
      {:ok, provider} -> {:ok, provider}
      :error -> {:error, :unknown_share_provider}
    end
  end

  defp share_provider(_share), do: {:error, :unknown_share_provider}

  defp share_aad(tenant_id, version, index) do
    @tenant_key_aad_prefix <> tenant_id <> "|" <> Integer.to_string(version) <> "|" <> Integer.to_string(index)
  end

  defp validate_volume_id(volume_id) when is_binary(volume_id) do
    if Regex.match?(@volume_id_format, volume_id), do: :ok, else: {:error, :invalid_volume_id}
  end

  defp validate_volume_id(_volume_id), do: {:error, :invalid_volume_id}

  defp validate_public_key(<<_::binary-size(@x25519_public_key_bytes)>>), do: :ok
  defp validate_public_key(_public_key), do: {:error, :invalid_public_key}

  defp ensure_available do
    if available?() do
      :ok
    else
      Logger.error("[Kura.VolumeKeys] root keys are not configured; refusing to issue volume keys")
      {:error, :root_keys_unavailable}
    end
  end

  defp authenticate(token) when is_binary(token) and token != "" do
    expected_username = Environment.kura_volumes_csi_node_username()

    case Client.create_bound_token_review(token, @audience, timeout: @kubernetes_timeout_ms) do
      {:ok, %{username: ^expected_username, extra: %{@node_name_extra => [node_name]}}}
      when is_binary(node_name) and node_name != "" ->
        {:ok, node_name}

      {:ok, _user} ->
        {:error, :unauthenticated}

      {:error, :unauthenticated} ->
        {:error, :unauthenticated}

      {:error, reason} ->
        {:error, {:kubernetes, reason}}
    end
  end

  defp authenticate(_token), do: {:error, :unauthenticated}

  defp authorize_volume(volume_id, node_name) do
    case Client.get_persistent_volume(volume_id, timeout: @kubernetes_timeout_ms) do
      {:ok, volume} ->
        volume_claim(volume, volume_id, node_name)

      {:error, :not_found} ->
        {:error, :volume_not_found}

      {:error, reason} ->
        {:error, {:kubernetes, reason}}
    end
  end

  defp volume_claim(%{"spec" => %{"csi" => csi, "claimRef" => claim_ref} = spec}, volume_id, node_name) do
    terms = get_in(spec, ["nodeAffinity", "required", "nodeSelectorTerms"])

    if csi["driver"] == @driver and csi["volumeHandle"] == volume_id and pinned_to_node?(terms, node_name) and
         claim_ref["namespace"] == @kura_namespace and present?(claim_ref["name"]) and present?(claim_ref["uid"]) do
      {:ok, claim_ref}
    else
      {:error, :forbidden}
    end
  end

  defp volume_claim(_volume, _volume_id, _node_name), do: {:error, :forbidden}

  # Node selector terms are ORed, so every term has to pin the node.
  defp pinned_to_node?([_ | _] = terms, node_name) do
    Enum.all?(terms, fn term ->
      term
      |> Map.get("matchExpressions", [])
      |> Enum.any?(&match?(%{"key" => @node_topology_key, "operator" => "In", "values" => [^node_name]}, &1))
    end)
  end

  defp pinned_to_node?(_terms, _node_name), do: false

  defp claim_account(%{"name" => claim_name, "uid" => claim_uid}, volume_id) do
    case Client.get_persistent_volume_claim(@kura_namespace, claim_name, timeout: @kubernetes_timeout_ms) do
      {:ok, claim} ->
        with %{"metadata" => %{"uid" => ^claim_uid, "labels" => %{@instance_label => instance}}, "spec" => spec}
             when is_binary(instance) <- claim,
             ^volume_id <- spec["volumeName"],
             %Account{} = account <- instance_account(instance) do
          {:ok, account}
        else
          _ -> {:error, :forbidden}
        end

      {:error, :not_found} ->
        {:error, :forbidden}

      {:error, reason} ->
        {:error, {:kubernetes, reason}}
    end
  end

  defp instance_account(instance) do
    account_ids =
      Repo.all(
        from(s in Server,
          where: s.provisioner_node_ref == ^instance and s.status != :destroyed,
          distinct: true,
          select: s.account_id
        )
      )

    case account_ids do
      [account_id] -> Repo.get(Account, account_id)
      _ -> nil
    end
  end

  defp tenant_key(account, nil), do: ensure_active_key(account)

  defp tenant_key(account, version) when is_integer(version) do
    case key_version(account, version) do
      %TenantKey{} = key -> {:ok, key}
      nil -> {:error, :key_version_not_found}
    end
  end

  defp present?(value), do: is_binary(value) and value != ""
end
