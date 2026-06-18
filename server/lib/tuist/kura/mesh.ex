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
  # There is no CRL/OCSP in Kura's peer verifier, so a node is revoked by no
  # longer re-signing its CSR and letting the leaf expire: the leaf lifetime is
  # the revocation latency. Nodes re-enroll on each boot today, so the leaf is
  # sized for an operational restart cadence; it can be shortened once nodes
  # support zero-downtime in-process rotation.
  @leaf_validity_days 30
  @leaf_renew_after_seconds 1_296_000

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
         peers: mesh_peers(account, exclude: node_url)
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
  Peer node URLs in the account's mesh: the account's enrolled self-hosted nodes.

  Bridging the Tuist-managed nodes' peer endpoint in is a follow-up: main's
  controller-managed mesh discovers managed peers through an in-cluster account
  peer Service, so seeding it to an internet-side self-hosted node needs that
  peer plane exposed publicly first.
  """
  def mesh_peers(%Account{} = account, opts \\ []) do
    exclude = Keyword.get(opts, :exclude)

    account
    |> self_hosted_peer_urls()
    |> Enum.reject(&(&1 == exclude))
  end

  defp self_hosted_peer_urls(%Account{} = account) do
    Repo.all(
      from(e in AccountCacheEndpoint,
        where: e.account_id == ^account.id and e.technology == :kura_self_hosted_peer,
        select: e.url
      )
    )
  end

  # The enrolled node's internal peer URL, recorded only for mesh discovery.
  # It is never a client-facing cache endpoint (that is the node's advertised
  # HTTP URL, reported via registration heartbeats), so it is stored under the
  # `kura_self_hosted_peer` technology and excluded from CLI endpoint lookup.
  defp register_node_endpoint(%Account{} = account, node_url) do
    %AccountCacheEndpoint{}
    |> AccountCacheEndpoint.create_changeset(%{
      account_id: account.id,
      url: node_url,
      technology: :kura_self_hosted_peer
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:account_id, :technology, :url])
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
end
