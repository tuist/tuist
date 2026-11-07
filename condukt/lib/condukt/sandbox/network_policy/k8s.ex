defmodule Condukt.Sandbox.NetworkPolicy.K8s do
  @moduledoc """
  Kubernetes-specific glue for the `Condukt.Sandbox.NetworkPolicy`
  egress layer.

  `Condukt.Sandbox.Kubernetes` calls into this module when an agent's
  sandbox spec sets `:network_policy`. The module owns:

    * Generating a per-session ephemeral CA (`Condukt.Sandbox.NetworkPolicy.CA`)
    * Creating and deleting the K8s `Secret` that delivers the CA and
      the policy JSON to the sidecar
    * Creating and deleting the `NetworkPolicy` that restricts pod
      egress so the sidecar is the only thing that can reach the
      outside world
    * Augmenting the pod spec with the `condukt-egress` init container
      and sidecar plus the secret/bundle volume mounts on the
      workspace container
    * Starting and stopping the BEAM-side control reader that decodes
      NDJSON events from the sidecar

  See `docs/guides/network-policy.md` for the full picture.
  """

  alias Condukt.Sandbox.NetworkPolicy
  alias Condukt.Sandbox.NetworkPolicy.CA
  alias Condukt.Sandbox.NetworkPolicy.Decider
  alias Condukt.Sandbox.NetworkPolicy.K8s.Manifests

  @doc """
  Builds the per-session manifests and resolved options. Called by
  `Condukt.Sandbox.Kubernetes` before pod creation.

  Returns `{:ok, %{policy: NetworkPolicy.t(), secret: map,
  network_policy: map, init_container: map, sidecar_container: map,
  secret_volume: map, workspace_volume_mounts: [map], ca: CA.t(),
  names: %{...}}}`.

  Input opts:

    * `:session_id` — required.
    * `:namespace` — required.
    * `:policy` — the `Condukt.Sandbox.NetworkPolicy` struct.
    * `:image`, `:proxy_port`, `:control_port`, `:sidecar_uid` —
      optional knobs for the sidecar container.
  """
  def prepare(opts) do
    session_id = Map.fetch!(opts, :session_id)
    namespace = Map.fetch!(opts, :namespace)
    policy = NetworkPolicy.new(Map.get(opts, :policy))
    image = Map.get(opts, :image) || Manifests.default_image()
    proxy_port = Map.get(opts, :proxy_port) || Manifests.default_proxy_port()
    control_port = Map.get(opts, :control_port) || Manifests.default_control_port()
    sidecar_uid = Map.get(opts, :sidecar_uid) || Manifests.default_sidecar_uid()

    with {:ok, ca} <- CA.generate(common_name: session_id) do
      policy_json = encode_policy(policy)
      secret_name = "condukt-net-" <> sanitize(session_id)
      netpol_name = "condukt-net-" <> sanitize(session_id)

      secret =
        Manifests.secret(%{
          name: secret_name,
          namespace: namespace,
          session_id: session_id,
          policy_json: policy_json,
          ca_cert_pem: ca.cert_pem,
          ca_key_pem: ca.key_pem,
          bundle_pem: CA.trust_bundle(ca)
        })

      network_policy =
        Manifests.network_policy(%{
          name: netpol_name,
          namespace: namespace,
          session_id: session_id
        })

      shared = %{
        image: image,
        proxy_port: proxy_port,
        control_port: control_port,
        sidecar_uid: sidecar_uid,
        session_id: session_id
      }

      init_container = Manifests.init_container(shared)
      sidecar_container = Manifests.sidecar_container(shared)
      secret_volume = Manifests.secret_volume(secret_name)
      workspace_volume_mounts = Manifests.workspace_secret_volume_mounts()

      {:ok,
       %{
         policy: policy,
         secret: secret,
         network_policy: network_policy,
         init_container: init_container,
         sidecar_container: sidecar_container,
         secret_volume: secret_volume,
         workspace_volume_mounts: workspace_volume_mounts,
         ca: ca,
         names: %{secret: secret_name, network_policy: netpol_name}
       }}
    end
  end

  @doc """
  Applies the prepared manifests to the cluster: creates the Secret
  and the NetworkPolicy. The pod spec gets the sidecar added by the
  caller; this function does not create the pod.
  """
  def apply(conn, %{secret: secret, network_policy: netpol}) do
    with {:ok, _} <- create_or_replace(conn, secret),
         {:ok, _} <- create_or_replace(conn, netpol) do
      :ok
    end
  end

  @doc """
  Removes the Secret and NetworkPolicy associated with a session.
  Called during `Condukt.Sandbox.Kubernetes` shutdown when
  `:delete_on_shutdown` is true. Errors are swallowed; teardown is
  best-effort.
  """
  def teardown(conn, namespace, %{secret: secret_name, network_policy: netpol_name}) do
    delete_resource(conn, "v1", "Secret", namespace, secret_name)
    delete_resource(conn, "networking.k8s.io/v1", "NetworkPolicy", namespace, netpol_name)
    :ok
  end

  defp encode_policy(%NetworkPolicy{} = policy) do
    JSON.encode!(%{
      rules: Enum.map(policy.rules, &encode_rule/1),
      default: Atom.to_string(policy.default),
      max_body_capture: policy.max_body_capture,
      redact: Enum.map(policy.redact, &Regex.source/1),
      decide_timeout_ms: decide_timeout_ms(policy)
    })
  end

  defp decide_timeout_ms(policy) do
    case Decider.policy_spec(policy) do
      nil -> 5_000
      spec -> spec.timeout
    end
  end

  # The sidecar evaluates `allow` and `deny` rules locally. `:decide`
  # becomes the wire signal that tells the sidecar to round-trip to
  # the BEAM; the bridge resolves the actual decider on its side, so
  # the wire form carries no decider payload.
  defp encode_rule({:allow, hosts}) when is_list(hosts) do
    %{type: "allow", hosts: hosts}
  end

  defp encode_rule({:deny, hosts}) when is_list(hosts) do
    %{type: "deny", hosts: hosts}
  end

  defp encode_rule({:decide, _callable}) do
    %{type: "decide"}
  end

  defp encode_rule(other) do
    raise ArgumentError,
          "unsupported NetworkPolicy rule for sidecar wire: #{inspect(other)}"
  end

  defp create_or_replace(conn, manifest) do
    case K8s.Client.run(K8s.Client.put_conn(K8s.Client.create(manifest), conn)) do
      {:ok, resource} ->
        {:ok, resource}

      {:error, %{message: "already exists" <> _}} ->
        replace(conn, manifest)

      {:error, %K8s.Client.APIError{reason: "AlreadyExists"}} ->
        replace(conn, manifest)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp replace(conn, manifest) do
    op = K8s.Client.update(manifest) |> K8s.Client.put_conn(conn)

    case K8s.Client.run(op) do
      {:ok, resource} -> {:ok, resource}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_resource(conn, api_version, kind, namespace, name) do
    op =
      K8s.Client.delete(api_version, kind, namespace: namespace, name: name)
      |> K8s.Client.put_conn(conn)

    K8s.Client.run(op)
  end

  defp sanitize(string) do
    string
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]/, "-")
    |> String.slice(0, 50)
  end
end
