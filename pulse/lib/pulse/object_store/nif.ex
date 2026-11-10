defmodule Pulse.ObjectStore.NIF do
  @moduledoc false

  # Distribute the compiled NIF via GitHub Releases (see
  # `.github/workflows/release.yml`), so a downstream consumer can install
  # Pulse without a Cargo toolchain. `force_build` defaults to false: a
  # `mix deps.get` of `:pulse` fetches the precompiled artifact matching
  # the consumer's OS + arch + NIF version from the tagged release. Local
  # dev and this repo's own CI set `PULSE_NIF_FORCE_BUILD=1` to compile
  # from source instead, which is what proves the source keeps building.
  use RustlerPrecompiled,
    otp_app: :pulse,
    crate: "pulse_object_store",
    base_url: "https://github.com/tuist/tuist/releases/download/pulse@#{Mix.Project.config()[:version]}",
    force_build: System.get_env("PULSE_NIF_FORCE_BUILD") in ["1", "true"],
    version: Mix.Project.config()[:version],
    targets: ~w(
      x86_64-unknown-linux-gnu
      x86_64-unknown-linux-musl
      aarch64-unknown-linux-gnu
      aarch64-unknown-linux-musl
      aarch64-apple-darwin
    ),
    nif_versions: ~w(2.16)

  # Request functions return `:ok` once the request is running and later send
  # `{reference, result}` to the caller; `Pulse.ObjectStore` waits for it.
  # Argument validation failures return `{:error, reason}` immediately.
  def put(_ref, _config, _key, _data), do: :erlang.nif_error(:nif_not_loaded)
  def put_if_none_match(_ref, _config, _key, _data), do: :erlang.nif_error(:nif_not_loaded)
  def put_if_match(_ref, _config, _key, _data, _etag), do: :erlang.nif_error(:nif_not_loaded)
  def get(_ref, _config, _key), do: :erlang.nif_error(:nif_not_loaded)
  def verify(_ref, _config, _key, _expected, _timeout_ms), do: :erlang.nif_error(:nif_not_loaded)
  def keyed_publication_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def snapshot_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def async_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def native_allocated_bytes, do: :erlang.nif_error(:nif_not_loaded)

  def get_snapshot(_ref, _config, _key, _etag, _suffix, _limit, _timeout_ms), do: :erlang.nif_error(:nif_not_loaded)

  def get_if_none_match(_ref, _config, _key, _etag), do: :erlang.nif_error(:nif_not_loaded)
  def retention_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def get_bounded(_ref, _config, _key, _etag, _limit), do: :erlang.nif_error(:nif_not_loaded)
  def list_page(_ref, _config, _prefix, _after, _limit), do: :erlang.nif_error(:nif_not_loaded)
  def discover_tenants(_ref, _config, _after, _limit), do: :erlang.nif_error(:nif_not_loaded)
  def delete_bounded(_ref, _config, _key), do: :erlang.nif_error(:nif_not_loaded)
  def delete(_ref, _config, _key), do: :erlang.nif_error(:nif_not_loaded)
  def list_prefixes(_ref, _config, _prefix), do: :erlang.nif_error(:nif_not_loaded)
  def list(_ref, _config, _prefix), do: :erlang.nif_error(:nif_not_loaded)
end
