defmodule Tuist.Kura.Mesh do
  @moduledoc """
  Signs the node certificates that let a customer's self-hosted Kura nodes join
  the account's mutually-authenticated mesh.

  The per-account peer CA is owned by the Kura controller (the `kura-<handle>-peer-ca`
  secret it maintains for an account whose managed instances run with `mesh`
  enabled). Enrollment reads that CA and signs the self-hosted node's CSR with
  it, so the node's leaf is trusted by the account's managed pods (which verify
  against the same CA) and vice versa.

  Node enrollment is the onboarding primitive: a node boots with only its
  tenant-scoped credential, the control-plane URL, and its own URL. It generates
  a keypair locally (the private key never leaves the customer's infrastructure),
  sends a CSR, and gets back its signed certificate, the account CA, the
  `tenant_id`, and the current peer list.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AccountCacheEndpoint
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura
  alias Tuist.Kura.Regions
  alias Tuist.Repo
  alias X509.Certificate.Extension

  @kura_namespace "kura"
  # Mesh heartbeat cadence the control plane advertises back to enrolled
  # nodes. Independent from the registration heartbeat: registration advertises
  # the node's client-facing endpoint (public plane), the mesh heartbeat proves
  # mesh-membership liveness (peer plane).
  @mesh_heartbeat_interval_seconds 60
  # How long an enrolled node may go without a mesh heartbeat (an enrollment
  # also counts as proof of life) before it is withheld from the mesh. This is
  # the mesh's entire safety margin: the moment a peer is withheld, every
  # node's next heartbeat drops it from the dynamic view and its queued
  # replication messages are dropped immediately, so the window stays many
  # missed heartbeats wide to keep a blip from costing a full re-bootstrap
  # on recovery.
  @stale_peer_after_minutes 30
  # There is no CRL/OCSP in Kura's peer verifier, so a node is revoked by no
  # longer re-signing its CSR and letting the leaf expire: the leaf lifetime is
  # the revocation latency. Nodes re-enroll on each boot today, so the leaf is
  # sized for an operational restart cadence; it can be shortened once nodes
  # support zero-downtime in-process rotation.
  @leaf_validity_days 30
  @leaf_renew_after_seconds 1_296_000

  def mesh_heartbeat_interval_seconds, do: @mesh_heartbeat_interval_seconds
  def stale_peer_after_minutes, do: @stale_peer_after_minutes

  @doc """
  Reads the account's controller-managed peer CA (the `kura-<handle>-peer-ca`
  secret the Kura controller maintains once the account has a managed instance
  running with `mesh` enabled). Returns `{:ok, %{certificate_pem, private_key_pem}}`,
  or `{:error, :ca_unavailable}` when there is no shared CA yet for a self-hosted
  node to join.
  """
  def read_account_peer_ca(%Account{} = account) do
    with {:ok, opts} <- account_cluster_opts(account),
         {:ok, %{"data" => data}} when is_map(data) <- Client.get(peer_ca_secret_path(account), opts: opts),
         {:ok, cert_pem} <- decode_pem(data["ca.pem"]),
         {:ok, key_pem} <- decode_pem(data["ca-key.pem"]) do
      {:ok, %{certificate_pem: cert_pem, private_key_pem: key_pem}}
    else
      _ -> {:error, :ca_unavailable}
    end
  end

  defp account_cluster_opts(%Account{} = account) do
    account.id
    |> Kura.list_servers_for_account()
    |> Enum.find_value({:error, :ca_unavailable}, fn server ->
      case Regions.get(server.region) do
        %Regions{provisioner_config: config} -> {:ok, Map.get(config, :kubernetes_client, [])}
        _ -> nil
      end
    end)
  end

  defp peer_ca_secret_path(%Account{name: name}) do
    "/api/v1/namespaces/#{@kura_namespace}/secrets/kura-#{String.downcase(name)}-peer-ca"
  end

  defp decode_pem(value) when is_binary(value), do: Base.decode64(value)
  defp decode_pem(_), do: :error

  @doc """
  Enrolls a node from its CSR, returning the signed certificate, the account CA,
  the `tenant_id`, the peer list, and when to renew. The node URL is registered
  as a self-hosted endpoint so the node joins the account's mesh and CLI cache
  resolution.
  """
  def enroll_node(%Account{} = account, %{csr: csr_pem, node_url: node_url}) do
    with {:ok, host} <- node_host(node_url),
         {:ok, certificate} <- sign_node_certificate(account, csr_pem, [host]) do
      register_node_endpoint(account, node_url)

      {:ok,
       %{
         tenant_id: account.name,
         certificate_pem: certificate.certificate_pem,
         ca_certificate_pem: certificate.ca_certificate_pem,
         not_after: certificate.not_after,
         renew_after_seconds: @leaf_renew_after_seconds,
         peers: mesh_peers(account, exclude: node_url),
         # Split out so the node can seed only platform-stable endpoints into
         # its static peer config; volatile (self-hosted) membership flows
         # exclusively through the heartbeat channel, so removals propagate
         # without a restart.
         managed_peers: managed_peer_urls(account)
       }}
    end
  end

  @doc """
  Signs a node CSR with the account CA. The certificate's SAN is set from
  `allowed_hosts` (the issuer controls it), not from the CSR, so a node cannot
  request a certificate for a host it does not own.
  """
  def sign_node_certificate(%Account{} = account, csr_pem, [primary_host | _] = allowed_hosts) do
    with {:ok, ca} <- read_account_peer_ca(account),
         {:ok, csr} <- parse_csr(csr_pem),
         :ok <- validate_csr(csr) do
      ca_certificate = X509.Certificate.from_pem!(ca.certificate_pem)
      ca_key = X509.PrivateKey.from_pem!(ca.private_key_pem)

      certificate =
        X509.Certificate.new(
          X509.CSR.public_key(csr),
          "/CN=#{primary_host}",
          ca_certificate,
          ca_key,
          template: :server,
          validity: @leaf_validity_days,
          extensions: [
            subject_alt_name: Extension.subject_alt_name(allowed_hosts)
          ]
        )

      {:ok,
       %{
         certificate_pem: X509.Certificate.to_pem(certificate),
         ca_certificate_pem: ca.certificate_pem,
         not_after: days_from_now(@leaf_validity_days)
       }}
    end
  end

  @doc """
  Peer node URLs in the account's mesh: the account's enrolled self-hosted nodes
  plus the public peer endpoint of each managed region the account runs in.

  Returning the managed endpoints seeds the self-hosted node to dial the managed
  mesh (the self-hosted->managed replication leg); the reverse leg is the
  controller injecting the self-hosted URLs into managed pods' `KURA_PEERS` (see
  `Tuist.Kura.Provisioner.KubernetesController`).
  """
  def mesh_peers(%Account{} = account, opts \\ []) do
    exclude = Keyword.get(opts, :exclude)

    (self_hosted_peer_urls(account) ++ managed_peer_urls(account))
    |> Enum.uniq()
    |> Enum.reject(&(&1 == exclude))
  end

  @doc """
  The account's enrolled self-hosted node peer URLs. These are the nodes' own
  `KURA_NODE_URL`s (recorded at enrollment), used both as mesh peers and as the
  external peers the managed pods dial back.
  """
  def self_hosted_peer_urls(%Account{} = account) do
    Repo.all(
      from(e in AccountCacheEndpoint,
        where:
          e.account_id == ^account.id and e.technology == :kura_self_hosted_peer and
            is_nil(e.deactivated_at),
        order_by: e.url,
        select: e.url
      )
    )
  end

  defp managed_peer_urls(%Account{} = account) do
    account.id
    |> Kura.list_servers_for_account()
    |> Enum.map(fn server ->
      case Regions.get(server.region) do
        %Regions{} = region -> Regions.peer_public_url(account.name, region)
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Records a mesh heartbeat from an enrolled self-hosted node: refreshes the
  liveness marker (`updated_at`) of the node's peer row, but only while the
  row is active. Returns the node's mesh view — whether it is currently a
  member and the current peer list, so heartbeats double as the peer-refresh
  channel (otherwise peers only refresh at certificate renewal).

  A deactivated, purged, or never-enrolled node is told `mesh_member: false`
  and recovers by re-enrolling — enrollment is the only path that creates or
  restores membership, and a recovery re-enrollment is the node's signal to
  re-bootstrap the data it missed while out of the mesh.

  The membership check and the marker bump are a single statement so a
  concurrent sweep or purge cannot be overwritten (or answered for) between a
  read and a write.
  """
  def heartbeat_node(%Account{} = account, node_url) when is_binary(node_url) do
    {count, _} =
      Repo.update_all(
        from(e in AccountCacheEndpoint,
          where:
            e.account_id == ^account.id and e.technology == :kura_self_hosted_peer and
              e.url == ^node_url and is_nil(e.deactivated_at)
        ),
        set: [updated_at: now()]
      )

    %{mesh_member: count > 0, peers: mesh_peers(account, exclude: node_url)}
  end

  @doc """
  Sweeps self-hosted peers that stopped sending mesh heartbeats. Peers whose
  liveness marker is older than the staleness window are deactivated —
  withheld from the mesh but kept, so a recovery re-enrollment from the
  returning node reactivates the row in place. Rows deactivated for longer
  than the peer-certificate lifetime are deleted: the node's leaf can no
  longer be valid, so rejoining requires re-enrollment (which recreates the
  row) anyway.

  Returns `%{deactivated: endpoints, purged: endpoints}`.

  Both statements re-check their predicate atomically (single
  `UPDATE`/`DELETE` with `RETURNING`), so a heartbeat or enrollment landing
  concurrently is never overwritten by a stale read.

  Deactivation cascades on its own: the peer disappears from enrollment and
  heartbeat responses, so every node's next heartbeat drops it from the
  dynamic peer set and its queued outbox messages are pruned after the grace
  window.
  """
  def sweep_stale_self_hosted_peers(opts \\ []) do
    stale_after_minutes = Keyword.get(opts, :stale_after_minutes, @stale_peer_after_minutes)
    now = now()
    cutoff = DateTime.add(now, -stale_after_minutes * 60, :second)

    {_count, deactivated} =
      Repo.update_all(
        from(e in AccountCacheEndpoint,
          where:
            e.technology == :kura_self_hosted_peer and is_nil(e.deactivated_at) and
              e.updated_at < ^cutoff,
          select: e
        ),
        set: [deactivated_at: now]
      )

    purge_cutoff = DateTime.add(now, -@leaf_validity_days * 24 * 60 * 60, :second)

    {_count, purged} =
      Repo.delete_all(
        from(e in AccountCacheEndpoint,
          where: e.technology == :kura_self_hosted_peer and e.deactivated_at < ^purge_cutoff,
          select: e
        )
      )

    %{deactivated: deactivated || [], purged: purged || []}
  end

  # The enrolled node's internal peer URL, recorded only for mesh discovery.
  # It is never a client-facing cache endpoint (that is the node's advertised
  # HTTP URL, reported via registration heartbeats), so it is stored under the
  # `kura_self_hosted_peer` technology and excluded from CLI endpoint lookup.
  # Re-enrollment bumps `updated_at` (the row's liveness marker for the stale
  # sweep) and reactivates a row deactivated while the node was away.
  defp register_node_endpoint(%Account{} = account, node_url) do
    %AccountCacheEndpoint{}
    |> AccountCacheEndpoint.create_changeset(%{
      account_id: account.id,
      url: node_url,
      technology: :kura_self_hosted_peer
    })
    |> Repo.insert(
      on_conflict: [set: [updated_at: now(), deactivated_at: nil]],
      conflict_target: [:account_id, :technology, :url]
    )
  end

  defp parse_csr(csr_pem) when is_binary(csr_pem) do
    case X509.CSR.from_pem(csr_pem) do
      {:ok, csr} -> {:ok, csr}
      {:error, _reason} -> {:error, :invalid_csr}
    end
  end

  defp parse_csr(_csr_pem), do: {:error, :invalid_csr}

  defp validate_csr(csr) do
    if X509.CSR.valid?(csr), do: :ok, else: {:error, :invalid_csr}
  end

  defp node_host(node_url) when is_binary(node_url) do
    case URI.parse(node_url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, host}

      _ ->
        {:error, :invalid_node_url}
    end
  end

  defp node_host(_node_url), do: {:error, :invalid_node_url}

  defp days_from_now(days) do
    DateTime.utc_now()
    |> DateTime.add(days * 24 * 60 * 60, :second)
    |> DateTime.truncate(:second)
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
