defmodule TuistCloud.AnalyticsTest do
  use ExUnit.Case, async: true
  import TelemetryTest
  alias TuistCloud.Analytics
  use Mimic

  setup [:telemetry_listen]

  @tag telemetry_listen: [:analytics, :organization, :create]
  describe "organization_create" do
    test "when analytics are enabled" do
      # When
      TuistCloud.Environment
      |> stub(:analytics_enabled?, fn -> true end)

      assert :ok =
               Analytics.organization_create("test", %{email: "test@tuist.io", id: 1})

      # Then
      assert_receive {:telemetry_event,
                      %{
                        event: [:analytics, :organization, :create],
                        measurements: %{email: "test@tuist.io", name: "test", user_id: 1},
                        metadata: %{}
                      }}
    end

    test "when analytics are disabled" do
      # When
      TuistCloud.Environment
      |> stub(:analytics_enabled?, fn -> false end)

      assert :ok =
               Analytics.organization_create("test", %{email: "test@tuist.io", id: 1})

      # Then
      refute_receive {:telemetry_event,
                      %{
                        event: [:analytics, :organization, :create],
                        measurements: %{email: "test@tuist.io", name: "test", user_id: 1},
                        metadata: %{}
                      }}
    end
  end

  @tag telemetry_listen: [:analytics, :user, :authenticate]
  describe "user_authenticate" do
    test "when analytics are enabled" do
      # When
      TuistCloud.Environment
      |> stub(:analytics_enabled?, fn -> true end)

      assert :ok = Analytics.user_authenticate(%{email: "test@tuist.io", id: 1})

      # Then
      assert_receive {:telemetry_event,
                      %{
                        event: [:analytics, :user, :authenticate],
                        measurements: %{email: "test@tuist.io", user_id: 1},
                        metadata: %{}
                      }}
    end

    test "when analytics are disabled" do
      # When
      TuistCloud.Environment
      |> stub(:analytics_enabled?, fn -> false end)

      assert :ok = Analytics.user_authenticate(%{email: "test@tuist.io", id: 1})

      # Then
      refute_receive {:telemetry_event,
                      %{
                        event: [:analytics, :user, :authenticate],
                        measurements: %{email: "test@tuist.io", user_id: 1},
                        metadata: %{}
                      }}
    end
  end
end
