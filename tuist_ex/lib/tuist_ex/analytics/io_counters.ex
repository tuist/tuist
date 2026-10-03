defmodule TuistEx.Analytics.IOCounters do
  @moduledoc false

  # Cumulative network and disk byte counters for the whole machine, the same
  # sources the Xcode command-line tool and the Gradle plugin read:
  #
  #   * Linux: `/proc/net/dev` and `/proc/diskstats`.
  #   * macOS: the per-interface link counters and the block storage driver
  #     statistics. Erlang cannot call those system interfaces directly, so
  #     they are read through `netstat` and `ioreg`, which take a few
  #     milliseconds each.
  #
  # A source that is missing or cannot be parsed reads as `nil`, never as
  # zero, so the caller can tell "no traffic" from "not measured".

  @netstat "/usr/sbin/netstat"
  @ioreg "/usr/sbin/ioreg"
  @sector_bytes 512

  @doc """
  Returns `%{network: {bytes_in, bytes_out} | nil, disk: {bytes_read, bytes_written} | nil}`.
  """
  def read do
    %{network: network(), disk: disk()}
  end

  defp network do
    cond do
      File.exists?("/proc/net/dev") ->
        with {:ok, text} <- File.read("/proc/net/dev"), do: parse_proc_net_dev(text)

      File.exists?(@netstat) ->
        with {:ok, text} <- command(@netstat, ["-ibn"]), do: parse_netstat(text)

      true ->
        nil
    end
    |> counters()
  end

  defp disk do
    cond do
      File.exists?("/proc/diskstats") ->
        with {:ok, text} <- File.read("/proc/diskstats"),
             do: parse_proc_diskstats(text, block_devices())

      File.exists?(@ioreg) ->
        with {:ok, text} <- command(@ioreg, ["-c", "IOBlockStorageDriver", "-r", "-w", "0"]),
             do: parse_ioreg(text)

      true ->
        nil
    end
    |> counters()
  end

  defp counters({first, second}) when is_integer(first) and is_integer(second),
    do: {first, second}

  defp counters(_unavailable), do: nil

  defp command(executable, args) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  # Whole disks only. `/proc/diskstats` also lists every partition and each
  # device-mapper or loop device stacked on a disk, which would count the
  # same bytes more than once.
  defp block_devices do
    case File.ls("/sys/block") do
      {:ok, names} -> Enum.reject(names, &String.starts_with?(&1, ["loop", "ram", "dm-", "zram"]))
      _ -> nil
    end
  end

  @doc false
  def parse_proc_net_dev(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.drop(2)
    |> sum_pairs(fn line ->
      line
      |> String.replace(":", " ")
      |> String.split()
      |> case do
        [_interface, bytes_in, _, _, _, _, _, _, _, bytes_out | _] ->
          {integer(bytes_in), integer(bytes_out)}

        _ ->
          nil
      end
    end)
  end

  @doc false
  def parse_proc_diskstats(text, devices) do
    text
    |> String.split("\n", trim: true)
    |> sum_pairs(fn line ->
      case String.split(line) do
        [_major, _minor, name, _, _, sectors_read, _, _, _, sectors_written | _] ->
          if is_nil(devices) or name in devices,
            do: {integer(sectors_read) * @sector_bytes, integer(sectors_written) * @sector_bytes}

        _ ->
          nil
      end
    end)
  end

  # Every interface appears once per address, with the same counters, so
  # only its link row counts. The address column is empty for some
  # interfaces, so the byte columns are read from the end of the row.
  @doc false
  def parse_netstat(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.contains?(&1, "<Link#"))
    |> sum_pairs(fn line ->
      line
      |> String.split()
      |> Enum.reverse()
      |> case do
        [_collisions, bytes_out, _errors_out, _packets_out, bytes_in | _] ->
          {integer(bytes_in), integer(bytes_out)}

        _ ->
          nil
      end
    end)
  end

  @doc false
  def parse_ioreg(text) do
    read = Regex.scan(~r/"Bytes \(Read\)"=(\d+)/, text, capture: :all_but_first)
    written = Regex.scan(~r/"Bytes \(Write\)"=(\d+)/, text, capture: :all_but_first)

    if !(read == [] and written == []) do
      {read |> List.flatten() |> Enum.map(&integer/1) |> Enum.sum(),
       written |> List.flatten() |> Enum.map(&integer/1) |> Enum.sum()}
    end
  end

  defp sum_pairs(lines, parse) do
    lines
    |> Enum.map(parse)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        nil

      pairs ->
        Enum.reduce(pairs, {0, 0}, fn {a, b}, {total_a, total_b} -> {total_a + a, total_b + b} end)
    end
  end

  defp integer(value) do
    case Integer.parse(value) do
      {number, _rest} -> number
      :error -> 0
    end
  end
end
