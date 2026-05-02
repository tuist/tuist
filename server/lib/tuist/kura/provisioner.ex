defmodule Tuist.Kura.Provisioner do
  @moduledoc """
  Behaviour the control plane uses to prepare backing resources, apply
  Kura to them, and destroy servers on a particular platform.

  The control plane (Oban workers, /ops UI, the `Tuist.Kura` context)
  speaks in regions and accounts. It does not know whether a given
  region is backed by a Helm release on a managed Kubernetes cluster,
  by a bare-metal Hetzner cloud server, or by a kind cluster on a
  developer laptop. Each backing platform is a module that implements
  this behaviour.

  Implementations return an opaque `provisioner_node_ref` from
  `provision/3`. The control plane stores it on the `Server` row
  and hands it back for every subsequent operation. Refs are
  provisioner-defined; the control plane never parses them.

  Adding a backing platform is self-contained: implement the
  callbacks, register the module against a region in
  `Tuist.Kura.Regions`, and supply whatever config the implementation
  needs (kubeconfig path, API token, instance-type table, …).
  """

  alias Tuist.Accounts.Account
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server

  @doc """
  Prepare or look up backing resources for `(account, region, server)`.

  Idempotent on the returned ref: calling twice for the same
  `(account_id, region)` should converge on the same backing resource
  rather than creating a second one. Implementations may rely on the
  partial unique index on `kura_servers` for the higher-level
  guarantee.

  The control plane treats this as the resource-allocation step. Some
  implementations may create resources here; others may only return a
  deterministic handle and defer the first install to `rollout/2`.
  """
  @callback provision(Account.t(), Regions.t(), Server.t()) ::
              {:ok, ref :: String.t()} | {:error, term()}

  @doc """
  Apply a (possibly new) Kura image tag to an existing provisioned
  resource.

  Used both for the first install (right after `provision/3`) and for
  later version changes. Implementations decide what "rollout" means:
  helm install or upgrade, ssh + systemctl restart, a multi-step warm
  rollout, etc.

  `inputs.on_log_line` is the sink for stdout/stderr the provisioner
  produces. The control plane batches those into ClickHouse and
  surfaces them in /ops.
  """
  @callback rollout(ref :: String.t(), inputs :: map()) :: :ok | {:error, term()}

  @doc """
  Destroy the backing resource. Must be safe to call on already-
  destroyed refs (return `:ok`) so the control plane can finalise the
  row after retries, even when a previous attempt already removed the
  backing resource before failing to persist local state.
  """
  @callback destroy(ref :: String.t(), Regions.t()) :: :ok | {:error, term()}

  @doc "Public URL the CLI hits for cache traffic."
  @callback public_url(account_handle :: String.t(), Regions.t(), ref :: String.t()) ::
              String.t()

  @doc """
  Best-effort drift check: what version is actually running on the
  node right now? Returns `{:ok, nil}` when the resource exists but
  isn't reporting a version yet. Used for reconciliation jobs and the
  /ops drift badge; never on the cache hot path.
  """
  @callback current_image_tag(ref :: String.t(), Regions.t()) ::
              {:ok, String.t() | nil} | {:error, term()}

  @doc """
  Translate a customer-facing `(spec, volume_size_gi)` pair into a
  provisioner-specific resource description, used by the provisioner
  during provisioning and rollout. Shape is implementation-defined.

  Kubernetes provisioners return Pod resource requests/limits;
  bare-metal provisioners would return an instance type and a block
  volume size. The customer-facing `Tuist.Kura.Specs` catalog stays
  free of any platform vocabulary.
  """
  @callback resources_for(Server.t()) :: map()

  ## Convenience dispatchers

  @doc "Calls `rollout/2` on the region's provisioner."
  def rollout(%Server{provisioner_node_ref: ref, region: region_id}, inputs) do
    with {:ok, region} <- Regions.fetch(region_id) do
      region.provisioner.rollout(ref, Map.put(inputs, :region, region))
    end
  end

  @doc "Calls `destroy/2` on the region's provisioner."
  def destroy(%Server{provisioner_node_ref: ref, region: region_id}) do
    with {:ok, region} <- Regions.fetch(region_id) do
      region.provisioner.destroy(ref, region)
    end
  end

  @doc "Calls `public_url/3` on the region's provisioner."
  def public_url(%Account{name: handle}, %Server{provisioner_node_ref: ref, region: region_id}) do
    with {:ok, region} <- Regions.fetch(region_id) do
      region.provisioner.public_url(handle, region, ref)
    end
  end

  @doc "Calls `current_image_tag/2` on the region's provisioner."
  def current_image_tag(%Server{provisioner_node_ref: ref, region: region_id}) do
    with {:ok, region} <- Regions.fetch(region_id) do
      region.provisioner.current_image_tag(ref, region)
    end
  end
end
