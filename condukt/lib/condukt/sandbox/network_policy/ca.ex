defmodule Condukt.Sandbox.NetworkPolicy.CA do
  @moduledoc """
  Per-session ephemeral Certificate Authority used by the egress sidecar
  for TLS interception.

  A CA is a self-signed root that the egress sidecar uses to mint per-host
  leaf certificates on the fly when intercepting TLS connections. The
  workspace image must trust this CA at session start for the handshake
  to succeed; if it does not, the request fails with a
  `tls_handshake_failed` event.

  ## Lifecycle

  One CA is generated per session at pod creation:

      {:ok, ca} = Condukt.Sandbox.NetworkPolicy.CA.generate(common_name: "session-abc")
      ca.cert_pem  # mounted as a K8s Secret to the sidecar
      ca.key_pem   # mounted as a K8s Secret to the sidecar
      ca.cert_pem  # also mounted (read-only) to the workspace at /etc/condukt/ca.pem

  When the session ends, the K8s Secret is deleted along with the pod, so
  the CA's blast radius is bounded by the session.

  ## Cryptographic choices

  Defaults are:

    * Elliptic curve P-256 (prime256v1). Faster than RSA, broadly supported,
      and the standard for short-lived certs.
    * Validity period: 24 hours, with a 1 hour pre-skew to absorb pod-vs-host
      clock drift.
    * Common name: a caller-supplied string, typically the session id.

  Custom defaults can be overridden via opts but the defaults match what the
  Kubernetes sandbox sets at session start.
  """

  alias X509.Certificate
  alias X509.Certificate.Extension
  alias X509.Certificate.Template
  alias X509.Certificate.Validity
  alias X509.PrivateKey

  @default_validity_hours 24
  @default_skew_hours 1

  @mozilla_bundle_path Path.expand("../../../../priv/ca-certificates/mozilla.pem", __DIR__)
  @external_resource @mozilla_bundle_path
  @mozilla_bundle File.read!(@mozilla_bundle_path)

  defstruct [
    :common_name,
    :cert_pem,
    :key_pem,
    :not_before,
    :not_after
  ]

  @doc """
  Generates a fresh per-session CA.

  Options:

    * `:common_name` — string put in the Subject CN. Required.
    * `:validity_hours` — total validity in hours, default `24`.
    * `:skew_hours` — pre-skew applied to NotBefore (and post-skew on
      NotAfter) in hours, default `1`. Absorbs clock drift between
      Condukt's host and the K8s pod.
    * `:organization` — Subject Organization, default `"Condukt"`.
  """
  def generate(opts) do
    common_name = Keyword.fetch!(opts, :common_name)
    validity_hours = Keyword.get(opts, :validity_hours, @default_validity_hours)
    skew_hours = Keyword.get(opts, :skew_hours, @default_skew_hours)
    organization = Keyword.get(opts, :organization, "Condukt")

    private_key = PrivateKey.new_ec(:secp256r1)

    now = DateTime.utc_now()
    not_before = DateTime.add(now, -skew_hours * 3600, :second)
    not_after = DateTime.add(now, (validity_hours + skew_hours) * 3600, :second)

    template = %Template{
      serial: {:random, 16},
      validity: Validity.new(not_before, not_after),
      hash: :sha256,
      extensions: [
        basic_constraints: Extension.basic_constraints(true),
        key_usage:
          Extension.key_usage([
            :digitalSignature,
            :keyCertSign,
            :cRLSign
          ]),
        subject_key_identifier: true,
        authority_key_identifier: true
      ]
    }

    subject_rdn = "/C=US/O=#{organization}/CN=#{common_name}"

    cert =
      Certificate.self_signed(
        private_key,
        subject_rdn,
        template: template
      )

    {:ok,
     %__MODULE__{
       common_name: common_name,
       cert_pem: Certificate.to_pem(cert),
       # `wrap: true` emits PKCS#8 (`-----BEGIN PRIVATE KEY-----`)
       # instead of SEC1 (`-----BEGIN EC PRIVATE KEY-----`). The
       # condukt-egress sidecar parses keys with rcgen's
       # `KeyPair::from_pem`, which is reliable on PKCS#8 but only
       # partially on SEC1.
       key_pem: PrivateKey.to_pem(private_key, wrap: true),
       not_before: not_before,
       not_after: not_after
     }}
  end

  @doc """
  Returns a PEM-encoded CA bundle suitable for mounting at
  `/etc/ssl/certs/ca-certificates.crt` and `/etc/ssl/cert.pem` on the
  workspace container.

  The bundle is the Mozilla / curl.se public root list (shipped under
  `priv/ca-certificates/mozilla.pem`) with the per-session CA
  appended. Any tool that reads the well-known bundle paths or
  honours `SSL_CERT_FILE` ends up trusting both the public Internet
  and the egress sidecar's leaf certs without the workspace image
  needing any preparation.
  """
  def trust_bundle(%__MODULE__{cert_pem: cert_pem}) do
    @mozilla_bundle <> "\n" <> cert_pem
  end

  @doc false
  def mozilla_bundle, do: @mozilla_bundle
end
