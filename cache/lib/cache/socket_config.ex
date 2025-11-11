defmodule Cache.SocketConfig do
  @moduledoc false

  @enforce_keys [:dir, :basename, :version, :path, :link]
  defstruct [:dir, :basename, :version, :path, :link]

  @fallback_key {__MODULE__, :fallback_version}

  def prepare_bind(num_acceptors) do
    case fetch() do
      {:ok, config} ->
        File.mkdir_p!(config.dir)
        _ = File.rm(config.path)

        http_config = [
          transport_module: ThousandIsland.Transports.UNIX,
          transport_options: [
            path: config.path,
            mode: 0o777,
            num_acceptors: num_acceptors
          ]
        ]

        {:ok, http_config, config}

      :error ->
        :error
    end
  end

  def fetch do
    with dir when is_binary(dir) <- System.get_env("PHX_SOCKET_DIR"),
         dir <- String.trim(dir),
         true <- dir != "" do
      {:ok, build_config(dir)}
    else
      _ -> :error
    end
  end

  defp build_config(dir) do
    basename = System.get_env("PHX_SOCKET_BASENAME") || "cache"

    version =
      System.get_env("PHX_SOCKET_VERSION") ||
        System.get_env("KAMAL_VERSION") ||
        System.get_env("RELEASE_VSN") ||
        fallback_version()

    %__MODULE__{
      dir: dir,
      basename: basename,
      version: version,
      path: Path.join(dir, "#{basename}-#{version}.sock"),
      link: Path.join(dir, "current.sock")
    }
  end

  defp fallback_version do
    case :persistent_term.get(@fallback_key, nil) do
      nil ->
        version = to_string(:erlang.system_time(:millisecond))
        :persistent_term.put(@fallback_key, version)
        version

      stored ->
        stored
    end
  end
end
