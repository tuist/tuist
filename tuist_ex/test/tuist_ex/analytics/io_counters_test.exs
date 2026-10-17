defmodule TuistEx.Analytics.IOCountersTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.IOCounters
  alias TuistEx.Analytics.MachineMetrics

  test "sums received and transmitted bytes across Linux interfaces" do
    text = """
    Inter-|   Receive                                                |  Transmit
     face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
        lo: 1000 10 0 0 0 0 0 0 2000 10 0 0 0 0 0 0
      eth0:5000 40 0 0 0 0 0 0 300 20 0 0 0 0 0 0
    """

    assert IOCounters.parse_proc_net_dev(text) == {6_000, 2_300}
  end

  test "counts whole Linux disks once, not their partitions or stacked devices" do
    text = """
     259       0 nvme0n1 100 0 2000 50 80 0 1000 40 0 90 90
     259       1 nvme0n1p1 90 0 1800 45 70 0 900 35 0 80 80
     253       0 dm-0 90 0 1800 45 70 0 900 35 0 80 80
    """

    assert IOCounters.parse_proc_diskstats(text, ["nvme0n1"]) == {2_000 * 512, 1_000 * 512}
  end

  test "reads each macOS interface once, whether or not it has an address" do
    text = """
    Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
    lo0        16384 <Link#1>                           100     0       1000      100     0       2000     0
    lo0        16384 127           127.0.0.1            100     -       1000      100     -       2000     -
    en0        1500  <Link#15>   6a:ea:20:e2:3a:c3      400     0       5000      200     0        300     0
    en0        1500  192.168.1     192.168.1.20         400     -       5000      200     -        300     -
    """

    assert IOCounters.parse_netstat(text) == {6_000, 2_300}
  end

  test "sums the bytes read and written by every macOS block storage driver" do
    text = """
    | "Statistics" = {"Operations (Write)"=1,"Bytes (Read)"=4096,"Bytes (Write)"=512,"Operations (Read)"=2}
    | "Statistics" = {"Bytes (Read)"=1000,"Errors (Write)"=0,"Bytes (Write)"=88}
    """

    assert IOCounters.parse_ioreg(text) == {5_096, 600}
  end

  test "output it cannot read is unavailable rather than zero" do
    assert IOCounters.parse_netstat("netstat: sysctl: Operation not permitted") == nil
    assert IOCounters.parse_ioreg("") == nil
    assert IOCounters.parse_proc_net_dev("") == nil
  end

  test "reads this machine's counters" do
    assert %{network: {bytes_in, bytes_out}, disk: {bytes_read, bytes_written}} =
             IOCounters.read()

    assert Enum.all?(
             [bytes_in, bytes_out, bytes_read, bytes_written],
             &(is_integer(&1) and &1 >= 0)
           )
  end

  test "counts memory the system can reclaim as unused, where the platform reports it" do
    assert MachineMetrics.used_memory_bytes(
             total_memory: 64,
             free_memory: 1,
             available_memory: 20
           ) == 44

    assert MachineMetrics.used_memory_bytes(total_memory: 64, free_memory: 1) == 63
  end

  test "turns two readings into bytes per second" do
    previous = %{network: {1_000, 500}, disk: {10_000, 0}}
    current = %{network: {3_000, 500}, disk: {10_000, 4_000}}

    assert MachineMetrics.rates(previous, current, 500) == %{
             network_bytes_in: 4_000,
             network_bytes_out: 0,
             disk_bytes_read: 0,
             disk_bytes_written: 8_000
           }
  end

  test "reports no throughput for a counter that is missing or went backwards" do
    assert MachineMetrics.rates(
             %{network: nil, disk: {900, 900}},
             %{network: {5, 5}, disk: {100, 950}},
             1_000
           ) == %{
             network_bytes_in: 0,
             network_bytes_out: 0,
             disk_bytes_read: 0,
             disk_bytes_written: 50
           }
  end
end
