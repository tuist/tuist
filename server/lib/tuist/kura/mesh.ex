defmodule Tuist.Kura.Mesh do
  @moduledoc """
  Issues the per-account certificate authority and node certificates that let a
  customer's self-hosted Kura nodes form a mutually-authenticated mesh.

  Node enrollment is the onboarding primitive: a node boots with only its
  tenant-scoped credential, the control-plane URL, and its own URL. It generates
  a keypair locally (the private key never leaves the customer's infrastructure),
  sends a CSR, and gets back its signed certificate, the account CA, the
  `tenant_id`, and the current peer list. Everything else self-configures.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AccountCacheEndpoint
  alias Tuist.FeatureFlags
  alias Tuist.Kura
  alias Tuist.Kura.MeshCertificateAuthority
  alias Tuist.Kura.Regions
  alias Tuist.Repo
  alias X509.Certificate.Extension

  # Five years for the account CA; nodes hold shorter-lived leaves they renew.
  @ca_validity_days 1825
  # There is no CRL/OCSP in Kura's peer verifier, so a node is revoked by no
  # longer re-signing its CSR and letting the leaf expire: the leaf lifetime is
  # the revocation latency. Nodes re-enroll on each boot today, so the leaf is
  # sized for an operational restart cadence; it can be shortened once nodes
  # support zero-downtime in-process rotation.
  @leaf_validity_days 30
  @leaf_renew_after_seconds 1_296_000

  @doc "Returns the account's mesh CA, generating it on first use."
  def get_or_create_certificate_authority(%Account{} = account) do
    case Repo.get_by(MeshCertificateAuthority, account_id: account.id) do
      %MeshCertificateAuthority{} = ca -> {:ok, ca}
      nil -> create_certificate_authority(account)
    end
  end

  defp create_certificate_authority(%Account{} = account) do
    ca_key = X509.PrivateKey.new_ec(:secp256r1)

    ca_certificate =
      X509.Certificate.self_signed(
        ca_key,
        "/CN=Tuist Kura Mesh CA/O=#{account.name}",
        template: :root_ca,
        validity: @ca_validity_days
      )

    attrs = %{
      account_id: account.id,
      certificate_pem: X509.Certificate.to_pem(ca_certificate),
      encrypted_private_key: X509.PrivateKey.to_pem(ca_key),
      not_after: days_from_now(@ca_validity_days)
    }

    case Repo.insert(MeshCertificateAuthority.create_changeset(attrs)) do
      {:ok, ca} ->
        {:ok, ca}

      {:error, %Ecto.Changeset{}} ->
        # Lost a race to create the single per-account CA; use the winner's.
        {:ok, Repo.get_by!(MeshCertificateAuthority, account_id: account.id)}
    end
  end

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
    with {:ok, ca} <- get_or_create_certificate_authority(account),
         {:ok, csr} <- parse_csr(csr_pem),
         :ok <- validate_csr(csr) do
      ca_certificate = X509.Certificate.from_pem!(ca.certificate_pem)
      ca_key = X509.PrivateKey.from_pem!(ca.encrypted_private_key)

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
  Issues a node certificate for a node whose keypair Tuist generates, signed by
  the account CA. Used for Tuist-managed mesh nodes (the customer's self-hosted
  nodes keep their private keys and use the CSR-based `sign_node_certificate/3`
  instead). Returns the certificate, its private key, and the account CA, all
  PEM-encoded.
  """
  def issue_node_certificate(%Account{} = account, [primary_host | _] = dns_names) do
    with {:ok, ca} <- get_or_create_certificate_authority(account) do
      ca_certificate = X509.Certificate.from_pem!(ca.certificate_pem)
      ca_key = X509.PrivateKey.from_pem!(ca.encrypted_private_key)
      node_key = X509.PrivateKey.new_ec(:secp256r1)

      certificate =
        X509.Certificate.new(
          X509.PublicKey.derive(node_key),
          "/CN=#{primary_host}",
          ca_certificate,
          ca_key,
          template: :server,
          validity: @leaf_validity_days,
          extensions: [
            subject_alt_name: Extension.subject_alt_name(dns_names)
          ]
        )

      {:ok,
       %{
         certificate_pem: X509.Certificate.to_pem(certificate),
         private_key_pem: X509.PrivateKey.to_pem(node_key),
         ca_certificate_pem: ca.certificate_pem
       }}
    end
  end

  @doc """
  Peer node URLs in the account's mesh. Today this is the account's registered
  self-hosted nodes; bridging in the Tuist-managed nodes' internal endpoints is
  a later slice (it needs a public internal-plane ingress).
  """
  def mesh_peers(%Account{} = account, opts \\ []) do
    exclude = Keyword.get(opts, :exclude)

    (self_hosted_peer_urls(account) ++ managed_peer_urls(account))
    |> Enum.uniq()
    |> Enum.reject(&(&1 == exclude))
  end

  defp self_hosted_peer_urls(%Account{} = account) do
    Repo.all(
      from(e in AccountCacheEndpoint,
        where: e.account_id == ^account.id and e.technology == :kura_self_hosted,
        select: e.url
      )
    )
  end

  # When the account bridges into the managed mesh, its self-hosted nodes also
  # need to reach the Tuist-managed regions, so we seed their peer list with each
  # managed region's public internal endpoint. Discovery expands these seeds to
  # the individual managed pods.
  defp managed_peer_urls(%Account{} = account) do
    if FeatureFlags.kura_enabled?(account) do
      account.id
      |> Kura.list_servers_for_account()
      |> Enum.flat_map(&managed_server_peer_urls(account, &1))
    else
      []
    end
  end

  defp managed_server_peer_urls(%Account{} = account, server) do
    case Regions.get(server.region) do
      %Regions{} = region ->
        case Regions.internal_public_peer_url(account.name, region) do
          nil -> []
          url -> [url]
        end

      _ ->
        []
    end
  end

  defp register_node_endpoint(%Account{} = account, node_url) do
    %AccountCacheEndpoint{}
    |> AccountCacheEndpoint.create_changeset(%{
      account_id: account.id,
      url: node_url,
      technology: :kura_self_hosted
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
