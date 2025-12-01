defmodule Tuist.Utilities.ThroughputFormatterTest do
  use ExUnit.Case, async: true

  alias Tuist.Utilities.ThroughputFormatter

  describe "format_throughput/1" do
    test "formats 1 Mbps correctly" do
      assert ThroughputFormatter.format_throughput(125_000) == "1.0 Mbps"
    end

    test "formats zero bytes per second" do
      assert ThroughputFormatter.format_throughput(0) == "0.0 Mbps"
    end

    test "formats fractional Mbps values" do
      # 625,000 bytes/s = 5.0 Mbps
      assert ThroughputFormatter.format_throughput(625_000) == "5.0 Mbps"

      # 156,250 bytes/s = 1.25 Mbps, rounded to 1.3
      assert ThroughputFormatter.format_throughput(156_250) == "1.3 Mbps"
    end

    test "formats large throughput values" do
      # 1,250,000,000 bytes/s = 10,000 Mbps (10 Gbps)
      assert ThroughputFormatter.format_throughput(1_250_000_000) == "10000.0 Mbps"
    end

    test "handles float input" do
      assert ThroughputFormatter.format_throughput(125_000.5) == "1.0 Mbps"
    end
  end
end
