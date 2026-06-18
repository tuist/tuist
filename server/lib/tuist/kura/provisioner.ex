defmodule Tuist.Kura.Provisioner do
  @moduledoc """
  Behaviour the control plane uses to prepare backing resources, apply
  Kura to them, and destroy servers on a particular platform.

  The control plane (`Tuist.Kura.Reconciler`, /ops UI, and the
  `Tuist.Kura` context) speaks in regions and accounts. It does not
  know whether a given region is backed by a Kubernetes custom resource,
  by a direct VM provisioner, or by another platform. Each backing
  platform is a module that implements this behaviour.

  Implementations return an opaque `provisioner_node_ref` from
  `provision/3`. The control plane stores it on the `Server` row
  and hands it back for every subsequent operation. Refs are
  provisioner-defined; the control plane never parses them.

  Adding a backing platform is self-contained: implement the
  callbacks, register the module against a region in
  `Tuist.Kura.Regions`, and supply whatever config the implementation
  needs (region host template, API token, instance-type table, …).
  """

  alias Tuist.Accounts
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
  creating a custom resource, ssh + systemctl restart, a multi-step warm
  rollout, etc. Durable status belongs in the deployment row and the
  backing resource status, not in captured stdout.
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
  Public gRPC (Bazel REAPI) URL for the server, or `nil` if the region
  doesn't expose gRPC publicly. Returned with a `grpcs://` scheme when
  TLS is terminated by the runtime.
  """
  @callback grpc_public_url(account_handle :: String.t(), Regions.t(), ref :: String.t()) ::
              String.t() | nil

  @doc """
  Best-effort drift check: what version is actually running on the
  node right now? Returns `{:ok, nil}` when the resource exists but
  isn't reporting a version yet. Used for reconciliation jobs and the
  /ops drift badge; never on the cache hot path.
  """
  @callback current_image_tag(ref :: String.t(), Regions.t()) ::
              {:ok, String.t() | nil} | {:error, term()}

  @doc """
  Returns the manifest revision currently applied to the backing resource.

  Provisioners that render declarative resources should use this to let
  the control plane re-apply config-only changes independently from Kura
  runtime image changes.
  """
  @callback current_manifest_revision(ref :: String.t(), Regions.t()) ::
              {:ok, String.t() | nil} | {:error, term()}

  @doc """
  Returns the manifest revision the provisioner currently renders for the
  account. The revision encodes account-dependent manifest content (such as
  mesh bridging), so a config change shifts the revision and the reconciler
  re-applies the manifest to a serving server in place.
  """
  @callback manifest_revision(Account.t()) :: String.t() | nil

  @doc "Returns the provisioner's default resource description for one Kura server."
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

  @doc "Calls `grpc_public_url/3` on the region's provisioner."
  def grpc_public_url(%Account{name: handle}, %Server{provisioner_node_ref: ref, region: region_id}) do
    with {:ok, region} <- Regions.fetch(region_id) do
      region.provisioner.grpc_public_url(handle, region, ref)
    end
  end

  @doc "Calls `current_image_tag/2` on the region's provisioner."
  def current_image_tag(%Server{provisioner_node_ref: ref, region: region_id}) do
    with {:ok, region} <- Regions.fetch(region_id) do
      region.provisioner.current_image_tag(ref, region)
    end
  end

  @doc "Calls `current_manifest_revision/2` on the region's provisioner."
  def current_manifest_revision(%Server{provisioner_node_ref: ref, region: region_id}) do
    with {:ok, region} <- Regions.fetch(region_id) do
      region.provisioner.current_manifest_revision(ref, region)
    end
  end

  @doc "Calls `manifest_revision/1` on the region's provisioner for the server's account."
  def manifest_revision(%Server{region: region_id} = server) do
    with {:ok, region} <- Regions.fetch(region_id),
         {:ok, account} <- Accounts.get_account_by_id(server.account_id) do
      {:ok, region.provisioner.manifest_revision(account)}
    end
  end
end
