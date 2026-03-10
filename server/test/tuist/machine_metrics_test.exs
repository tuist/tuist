defmodule Tuist.MachineMetricsTest do
  use TuistTestSupport.Cases.DataCase

  import Ecto.Query

  alias Tuist.Builds.BuildMachineMetric
  alias Tuist.ClickHouseRepo

  @base_timestamp 1_741_500_000.0

  defp sample_metrics do
    [
      %{
        timestamp: @base_timestamp + 1.0,
        cpu_usage_percent: 45.5,
        memory_used_bytes: 8_000_000_000,
        memory_total_bytes: 16_000_000_000,
        network_bytes_in: 1_000_000,
        network_bytes_out: 500_000,
        disk_bytes_read: 2_000_000,
        disk_bytes_written: 1_500_000
      },
      %{
        timestamp: @base_timestamp + 2.0,
        cpu_usage_percent: 72.3,
        memory_used_bytes: 10_000_000_000,
        memory_total_bytes: 16_000_000_000,
        network_bytes_in: 2_000_000,
        network_bytes_out: 1_000_000,
        disk_bytes_read: 3_000_000,
        disk_bytes_written: 2_500_000
      }
    ]
  end

  describe "Xcode build machine metrics" do
    test "creates machine metrics via Builds.create_build" do
      project_id = TuistTestSupport.Fixtures.ProjectsFixtures.project_fixture().id
      account_id = TuistTestSupport.Fixtures.AccountsFixtures.user_fixture(preload: [:account]).account.id

      {:ok, build} =
        Tuist.Builds.create_build(%{
          id: UUIDv7.generate(),
          duration: 1000,
          macos_version: "11.2.3",
          xcode_version: "12.4",
          is_ci: false,
          model_identifier: "Mac15,6",
          scheme: "App",
          project_id: project_id,
          account_id: account_id,
          status: "success",
          issues: [],
          files: [],
          targets: [],
          machine_metrics: sample_metrics()
        })

      metrics =
        ClickHouseRepo.all(
          from(m in BuildMachineMetric, where: m.build_run_id == ^build.id, order_by: [asc: m.timestamp])
        )

      assert length(metrics) == 2
      assert_in_delta Enum.at(metrics, 0).timestamp, @base_timestamp + 1.0, 0.001
      assert_in_delta Enum.at(metrics, 0).cpu_usage_percent, 45.5, 0.01
      assert Enum.at(metrics, 0).memory_used_bytes == 8_000_000_000
      assert_in_delta Enum.at(metrics, 1).timestamp, @base_timestamp + 2.0, 0.001
      assert_in_delta Enum.at(metrics, 1).cpu_usage_percent, 72.3, 0.01
      assert Enum.at(metrics, 0).gradle_build_id == nil
    end
  end
end
