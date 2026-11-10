defmodule Condukt.Bashkit.NIF do
  @moduledoc false
  # Low-level NIF binding to the bashkit virtual sandbox crate. This module
  # is internal: callers should use `Condukt.Sandbox.Virtual` and the
  # `Condukt.Sandbox.*` facade.
  #
  # When `CONDUKT_BASHKIT_DISABLE=1` is set at compile time the module is
  # generated as plain Elixir stubs that raise when called: no Rust
  # toolchain is invoked, no `.so` is mapped into the BEAM, and BEAM
  # teardown is unaffected. Use this on environments where the bashkit
  # NIF cannot be loaded safely (currently: GHA Linux runners, where a
  # loaded NIF triggers a teardown segfault under investigation).

  if System.get_env("CONDUKT_BASHKIT_DISABLE") in ["1", "true"] do
    # Disabled stubs return an :error tuple instead of raising so they
    # don't get inferred as `none()` by the Elixir 1.19 typer (which
    # would mark every `case`/`with` clause that matched success as
    # unreachable, breaking --warnings-as-errors). The default test
    # suite excludes :virtual_sandbox so these are never invoked anyway.
    @disabled_error {:error, :nif_disabled}

    def new_session(_mounts), do: @disabled_error
    def shutdown(_session), do: :ok
    def exec(_session, _command, _timeout_ms), do: @disabled_error
    def read_file(_session, _path), do: @disabled_error
    def write_file(_session, _path, _content), do: @disabled_error
    def edit_file(_session, _path, _old_text, _new_text), do: @disabled_error
    def glob(_session, _pattern, _cwd), do: @disabled_error
    def grep(_session, _pattern, _path, _case_sensitive, _file_glob), do: @disabled_error
    def mount(_session, _host_path, _vfs_path, _mode), do: @disabled_error
    def unmount(_session, _vfs_path), do: @disabled_error
  else
    use RustlerPrecompiled,
      otp_app: :condukt,
      crate: "condukt_bashkit",
      base_url: "https://github.com/tuist/tuist/releases/download/condukt@#{Mix.Project.config()[:version]}",
      force_build:
        System.get_env("CONDUKT_BASHKIT_PRECOMPILED") not in ["1", "true"] and
          (Mix.env() == :dev or
             System.get_env("CONDUKT_BASHKIT_BUILD") in ["1", "true"]),
      version: Mix.Project.config()[:version],
      targets: ~w(
        aarch64-apple-darwin
        aarch64-unknown-linux-gnu
        x86_64-apple-darwin
        x86_64-pc-windows-msvc
        x86_64-unknown-linux-gnu
      ),
      nif_versions: ~w(2.16 2.17)

    def new_session(_mounts), do: err()
    def shutdown(_session), do: err()
    def exec(_session, _command, _timeout_ms), do: err()
    def read_file(_session, _path), do: err()
    def write_file(_session, _path, _content), do: err()
    def edit_file(_session, _path, _old_text, _new_text), do: err()
    def glob(_session, _pattern, _cwd), do: err()
    def grep(_session, _pattern, _path, _case_sensitive, _file_glob), do: err()
    def mount(_session, _host_path, _vfs_path, _mode), do: err()
    def unmount(_session, _vfs_path), do: err()

    defp err, do: :erlang.nif_error(:nif_not_loaded)
  end
end
