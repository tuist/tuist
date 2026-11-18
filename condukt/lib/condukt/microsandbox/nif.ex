defmodule Condukt.Microsandbox.NIF do
  @moduledoc false
  # Low-level NIF binding to the microsandbox crate. Callers should use
  # `Condukt.Sandbox.Microsandbox` rather than this module.
  #
  # When `CONDUKT_MICROSANDBOX_DISABLE=1` is set at compile time the module is
  # generated as plain Elixir stubs, exactly as `CONDUKT_MICROSANDBOX_BUILD`
  # forces the opposite. Releases that bundle the library into a portable
  # binary need this: burrito's linux wrapper runs a musl runtime, and the
  # precompiled artifacts for this crate are glibc-linked, so a bundled `.so`
  # could not be loaded there. Embedded code loading means every module in a
  # release is loaded at boot, so an unloadable NIF is a boot failure rather
  # than a lazily surfaced one.

  @microsandbox_supported_target (
                                   arch =
                                     :erlang.system_info(:system_architecture) |> List.to_string()

                                   disabled? =
                                     System.get_env("CONDUKT_MICROSANDBOX_DISABLE") in ["1", "true"]

                                   cond do
                                     disabled? ->
                                       false

                                     match?({:unix, :darwin}, :os.type()) ->
                                       String.starts_with?(arch, "aarch64")

                                     match?({:unix, :linux}, :os.type()) ->
                                       String.starts_with?(arch, "aarch64") or
                                         String.starts_with?(arch, "x86_64")

                                     true ->
                                       false
                                   end
                                 )

  if @microsandbox_supported_target do
    use RustlerPrecompiled,
      otp_app: :condukt,
      crate: "condukt_microsandbox",
      base_url: "https://github.com/tuist/tuist/releases/download/condukt@#{Mix.Project.config()[:version]}",
      force_build:
        Mix.env() in [:dev, :test] or
          System.get_env("CONDUKT_MICROSANDBOX_BUILD") in ["1", "true"],
      version: Mix.Project.config()[:version],
      targets: ~w(
        aarch64-apple-darwin
        aarch64-unknown-linux-gnu
        x86_64-unknown-linux-gnu
      ),
      nif_versions: ~w(2.16 2.17)

    def new_session(_config), do: err()
    def shutdown(_session), do: err()
    def exec(_session, _shell, _command, _cwd, _env, _timeout_ms), do: err()
    def read_file(_session, _path), do: err()
    def write_file(_session, _path, _content), do: err()

    defp err, do: :erlang.nif_error(:nif_not_loaded)
  else
    @disabled_error {:error, :unsupported_target}

    def new_session(_config), do: @disabled_error
    def shutdown(_session), do: :ok
    def exec(_session, _shell, _command, _cwd, _env, _timeout_ms), do: @disabled_error
    def read_file(_session, _path), do: @disabled_error
    def write_file(_session, _path, _content), do: @disabled_error
  end
end
