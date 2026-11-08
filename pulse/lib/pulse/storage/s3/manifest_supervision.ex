defmodule Pulse.Storage.S3.ManifestSupervision do
  @moduledoc """
  Supervision tree fragment for the manifest layer.

  Runs nine children in this order:

    1. `Pulse.Storage.S3.ManifestRegistry` — via-name lookup for owners.
    2. `Pulse.Storage.S3.ManifestSupervisor` — `DynamicSupervisor`
       parenting the per-tenant owner processes.
    3. `Pulse.Storage.S3.ManifestCache` — the ETS-backed hot-path
       cache. Started last so any prior owner-recovery attempt hits an
       empty table cleanly.
    4. `Pulse.Storage.S3.AppendRegistry` — optional unkeyed buffer lookup.
    5. `Pulse.Storage.S3.AppendSupervisor` — bounded input buffers. Buffers
       are created only when ingest coalescing is enabled.
    6. `Pulse.Storage.S3.MetadataCache` — bounded, disposable immutable page cache.
    7. `Pulse.Storage.S3.ObjectCache` — disposable read cache of immutable segments.
    8. `Pulse.Storage.S3.RetentionAdmission` — node-wide monitored DELETE slots.
    9. `Pulse.Storage.S3.MetricMetadataStore` — bounded node-local record of
       metric metadata already published today.

  Wired into `Pulse.Application` only when the S3 adapter is active.
  """

  use Pulse.Runtime.Supervision

  alias Pulse.Runtime.Registry
  alias Pulse.Runtime.Supervision, as: Supervisor
  alias Pulse.Storage.S3.AppendRegistry
  alias Pulse.Storage.S3.AppendSupervisor
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ManifestRegistry
  alias Pulse.Storage.S3.ManifestSupervisor
  alias Pulse.Storage.S3.MetadataCache
  alias Pulse.Storage.S3.MetricMetadataStore
  alias Pulse.Storage.S3.ObjectCache
  alias Pulse.Storage.S3.RetentionAdmission

  @spec start_link(keyword()) :: Elixir.Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: ManifestRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: ManifestSupervisor},
      ManifestCache,
      {Registry, keys: :unique, name: AppendRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: AppendSupervisor},
      MetadataCache,
      ObjectCache,
      RetentionAdmission,
      MetricMetadataStore
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
