defmodule Pulse.OTLP.GRPC.NIF do
  @moduledoc false

  # The OTLP/gRPC transport (tonic) lives in its own crate so the codec NIF
  # stays free of an async runtime. Distributed like the other crates; see
  # `Pulse.ObjectStore.NIF` for the precompiled-artifact rationale.
  use RustlerPrecompiled,
    otp_app: :pulse,
    crate: "pulse_grpc",
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

  def otlp_grpc_api_version, do: :erlang.nif_error(:nif_not_loaded)
  def native_allocated_bytes, do: :erlang.nif_error(:nif_not_loaded)

  def otlp_grpc_start(_ip, _port, _owner, _max_message_bytes, _max_in_flight, _timeout_ms),
    do: :erlang.nif_error(:nif_not_loaded)

  def otlp_grpc_stop(_listener), do: :erlang.nif_error(:nif_not_loaded)
  def otlp_grpc_reply(_reply, _code, _message, _body), do: :erlang.nif_error(:nif_not_loaded)
end
