defmodule Tuist.Net do
  @moduledoc """
  Low-level networking helpers that need to drop below Erlang's
  `:gen_tcp` / `:inet` option API.
  """

  # IPPROTO_TCP — same on Linux and macOS.
  @ipproto_tcp 6

  # Linux <netinet/tcp.h>
  @linux_tcp_keepidle 4
  @linux_tcp_keepintvl 5
  @linux_tcp_keepcnt 6

  # macOS <netinet/tcp.h> (BSD-derived). `TCP_KEEPALIVE` plays the
  # role of Linux's `TCP_KEEPIDLE`.
  @darwin_tcp_keepalive 0x10
  @darwin_tcp_keepintvl 0x101
  @darwin_tcp_keepcnt 0x102

  @keepalive_idle_seconds 60
  @keepalive_interval_seconds 15
  @keepalive_probe_count 4

  @doc """
  Raw socket options that tighten TCP keepalive timing for connections
  held in long-lived pools (ClickHouse Cloud over public-internet HTTPS).

  `:gen_tcp` only exposes `SO_KEEPALIVE` as `keepalive: true`; setting
  the per-connection probe timing requires raw `{:raw, Proto, Opt, Bin}`
  tuples whose option numbers differ between Linux and macOS. Returns
  `[]` on platforms we don't recognize so the pool falls back to OS
  keepalive defaults.
  """
  def tcp_keepalive_raw_opts do
    case :os.type() do
      {:unix, :linux} ->
        [
          raw(@linux_tcp_keepidle, @keepalive_idle_seconds),
          raw(@linux_tcp_keepintvl, @keepalive_interval_seconds),
          raw(@linux_tcp_keepcnt, @keepalive_probe_count)
        ]

      {:unix, :darwin} ->
        [
          raw(@darwin_tcp_keepalive, @keepalive_idle_seconds),
          raw(@darwin_tcp_keepintvl, @keepalive_interval_seconds),
          raw(@darwin_tcp_keepcnt, @keepalive_probe_count)
        ]

      _ ->
        []
    end
  end

  defp raw(opt, value), do: {:raw, @ipproto_tcp, opt, <<value::native-32>>}
end
