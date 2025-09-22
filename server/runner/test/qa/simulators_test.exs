defmodule Runner.QA.Simulators.SimulatorsTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Runner.QA.Simulators
  alias Runner.QA.Simulators.SimulatorDevice

  describe "devices/1" do
    test "returns all devices when no runtime filter is provided" do
      # Given
      simctl_output = %{
        "devices" => %{
          "com.apple.CoreSimulator.SimRuntime.iOS-18-4" => [
            %{
              "name" => "iPhone 16 Pro",
              "udid" => "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
              "state" => "Shutdown"
            }
          ],
          "com.apple.CoreSimulator.SimRuntime.iOS-18-2" => [
            %{
              "name" => "iPhone 15",
              "udid" => "B9AE3970-30C9-438D-B0CB-8C7A84E2DB77",
              "state" => "Booted"
            }
          ]
        }
      }

      stub(System, :cmd, fn "xcrun", ["simctl", "list", "devices", "--json"] ->
        {JSON.encode!(simctl_output), 0}
      end)

      # When
      {:ok, devices} = Simulators.devices()

      # Then
      assert Enum.sort_by(devices, & &1.name) == [
               %SimulatorDevice{
                 name: "iPhone 15",
                 udid: "B9AE3970-30C9-438D-B0CB-8C7A84E2DB77",
                 state: "Booted",
                 runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-2"
               },
               %SimulatorDevice{
                 name: "iPhone 16 Pro",
                 udid: "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
                 state: "Shutdown",
                 runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-4"
               }
             ]
    end

    test "returns devices filtered by runtime identifier" do
      # Given
      simctl_output = %{
        "devices" => %{
          "com.apple.CoreSimulator.SimRuntime.iOS-18-4" => [
            %{
              "name" => "iPhone 16 Pro",
              "udid" => "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
              "state" => "Shutdown",
              "deviceTypeIdentifier" => "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
              "isAvailable" => true
            },
            %{
              "name" => "iPad Pro",
              "udid" => "10196E78-3BAC-485A-9264-201A5111FB5F",
              "state" => "Shutdown"
            }
          ],
          "com.apple.CoreSimulator.SimRuntime.iOS-18-2" => [
            %{
              "name" => "iPhone 15",
              "udid" => "B9AE3970-30C9-438D-B0CB-8C7A84E2DB77",
              "state" => "Booted"
            }
          ]
        }
      }

      stub(System, :cmd, fn "xcrun", ["simctl", "list", "devices", "--json"] ->
        {JSON.encode!(simctl_output), 0}
      end)

      # When
      {:ok, devices} =
        Simulators.devices(runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-4")

      # Then

      assert Enum.sort_by(devices, & &1.name) == [
               %SimulatorDevice{
                 name: "iPad Pro",
                 udid: "10196E78-3BAC-485A-9264-201A5111FB5F",
                 state: "Shutdown",
                 runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-4"
               },
               %SimulatorDevice{
                 name: "iPhone 16 Pro",
                 udid: "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
                 state: "Shutdown",
                 runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-4"
               }
             ]
    end

    test "returns empty list when no devices exist" do
      # Given
      simctl_output = %{"devices" => %{}}

      stub(System, :cmd, fn "xcrun", ["simctl", "list", "devices", "--json"] ->
        {JSON.encode!(simctl_output), 0}
      end)

      # When
      {:ok, devices} = Simulators.devices()

      # Then
      assert devices == []
    end

    test "returns error when xcrun command fails" do
      # Given
      stub(System, :cmd, fn "xcrun", ["simctl", "list", "devices", "--json"] ->
        {"Command failed", 1}
      end)

      # When
      result = Simulators.devices()

      # Then
      assert {:error, "Listing devices failed with: Command failed"} = result
    end

    test "returns devices filtered by name" do
      # Given
      simctl_output = %{
        "devices" => %{
          "com.apple.CoreSimulator.SimRuntime.iOS-18-4" => [
            %{
              "name" => "iPhone 16 Pro",
              "udid" => "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
              "state" => "Shutdown"
            },
            %{
              "name" => "iPhone 16",
              "udid" => "B9AE3970-30C9-438D-B0CB-8C7A84E2DB77",
              "state" => "Shutdown"
            }
          ],
          "com.apple.CoreSimulator.SimRuntime.iOS-18-2" => [
            %{
              "name" => "iPhone 16",
              "udid" => "1E2FAD90-37E5-45C0-9884-FB6551E0752D",
              "state" => "Booted"
            }
          ]
        }
      }

      stub(System, :cmd, fn "xcrun", ["simctl", "list", "devices", "--json"] ->
        {JSON.encode!(simctl_output), 0}
      end)

      # When
      {:ok, devices} = Simulators.devices(name: "iPhone 16")

      # Then
      assert Enum.sort_by(devices, & &1.udid) == [
               %SimulatorDevice{
                 name: "iPhone 16",
                 udid: "1E2FAD90-37E5-45C0-9884-FB6551E0752D",
                 state: "Booted",
                 runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-2"
               },
               %SimulatorDevice{
                 name: "iPhone 16",
                 runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-4",
                 state: "Shutdown",
                 udid: "B9AE3970-30C9-438D-B0CB-8C7A84E2DB77"
               }
             ]
    end

    test "returns devices filtered by both runtime and name" do
      # Given
      simctl_output = %{
        "devices" => %{
          "com.apple.CoreSimulator.SimRuntime.iOS-18-4" => [
            %{
              "name" => "iPhone 16 Pro",
              "udid" => "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
              "state" => "Shutdown",
              "deviceTypeIdentifier" => "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
              "isAvailable" => true
            },
            %{
              "name" => "iPhone 16",
              "udid" => "B9AE3970-30C9-438D-B0CB-8C7A84E2DB77",
              "state" => "Shutdown",
              "deviceTypeIdentifier" => "com.apple.CoreSimulator.SimDeviceType.iPhone-16",
              "isAvailable" => true
            }
          ],
          "com.apple.CoreSimulator.SimRuntime.iOS-18-2" => [
            %{
              "name" => "iPhone 16",
              "udid" => "1E2FAD90-37E5-45C0-9884-FB6551E0752D",
              "state" => "Booted",
              "deviceTypeIdentifier" => "com.apple.CoreSimulator.SimDeviceType.iPhone-16",
              "isAvailable" => false
            }
          ]
        }
      }

      stub(System, :cmd, fn "xcrun", ["simctl", "list", "devices", "--json"] ->
        {JSON.encode!(simctl_output), 0}
      end)

      # When
      {:ok, devices} =
        Simulators.devices(
          runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-4",
          name: "iPhone 16"
        )

      # Then
      assert devices == [
               %SimulatorDevice{
                 name: "iPhone 16",
                 runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-4",
                 state: "Shutdown",
                 udid: "B9AE3970-30C9-438D-B0CB-8C7A84E2DB77"
               }
             ]
    end

    test "returns empty list when no devices match the name filter" do
      # Given
      simctl_output = %{
        "devices" => %{
          "com.apple.CoreSimulator.SimRuntime.iOS-18-4" => [
            %{
              "name" => "iPhone 16 Pro",
              "udid" => "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
              "state" => "Shutdown",
              "deviceTypeIdentifier" => "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
              "isAvailable" => true
            }
          ]
        }
      }

      stub(System, :cmd, fn "xcrun", ["simctl", "list", "devices", "--json"] ->
        {JSON.encode!(simctl_output), 0}
      end)

      # When
      result = Simulators.devices(name: "iPhone 15")

      # Then
      assert {:ok, []} = result
    end
  end

  describe "boot_simulator/1" do
    test "returns ok when device is already booted" do
      # Given
      device = %SimulatorDevice{
        name: "iPhone 16",
        udid: "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
        state: "Booted",
        runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-4"
      }

      # When
      result = Simulators.boot_simulator(device)

      # Then
      assert result == :ok
    end

    test "boots device successfully when shutdown" do
      # Given
      device = %SimulatorDevice{
        name: "iPhone 16",
        udid: "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
        state: "Shutdown",
        runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-4"
      }

      stub(System, :cmd, fn "xcrun", ["simctl", "boot", "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1"] ->
        {"", 0}
      end)

      # When
      result = Simulators.boot_simulator(device)

      # Then
      assert result == :ok
    end

    test "returns error when boot fails" do
      # Given
      device = %SimulatorDevice{
        name: "iPhone 16",
        udid: "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
        state: "Shutdown",
        runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-4"
      }

      stub(System, :cmd, fn "xcrun", ["simctl", "boot", "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1"] ->
        {"Unable to boot device", 1}
      end)

      # When
      result = Simulators.boot_simulator(device)

      # Then
      assert {:error, "Failed to boot simulator: Unable to boot device"} = result
    end
  end

  describe "install_app/2" do
    test "installs app successfully" do
      # Given
      app_path = "/path/to/MyApp.app"

      device = %SimulatorDevice{
        name: "iPhone 16",
        udid: "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
        state: "Booted",
        runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-4"
      }

      stub(System, :cmd, fn "xcrun",
                            [
                              "simctl",
                              "install",
                              "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
                              ^app_path
                            ] ->
        {"", 0}
      end)

      # When
      result = Simulators.install_app(app_path, device)

      # Then
      assert result == :ok
    end

    test "returns error when installation fails" do
      # Given
      app_path = "/path/to/MyApp.app"

      device = %SimulatorDevice{
        name: "iPhone 16",
        udid: "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
        state: "Booted",
        runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-4"
      }

      stub(System, :cmd, fn "xcrun",
                            [
                              "simctl",
                              "install",
                              "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
                              ^app_path
                            ] ->
        {"Failed to install app", 1}
      end)

      # When
      result = Simulators.install_app(app_path, device)

      # Then
      assert {:error, "Failed to install app: Failed to install app"} = result
    end
  end

  describe "launch_app/2" do
    test "launches app successfully" do
      # Given
      bundle_identifier = "com.example.myapp"

      device = %SimulatorDevice{
        name: "iPhone 16",
        udid: "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
        state: "Booted",
        runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-4"
      }

      stub(System, :cmd, fn "xcrun",
                            [
                              "simctl",
                              "launch",
                              "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
                              ^bundle_identifier,
                              ""
                            ] ->
        {"com.example.myapp: 12345", 0}
      end)

      # When
      result = Simulators.launch_app(bundle_identifier, device)

      # Then
      assert result == :ok
    end

    test "returns error when launch fails" do
      # Given
      bundle_identifier = "com.example.myapp"

      device = %SimulatorDevice{
        name: "iPhone 16",
        udid: "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
        state: "Booted",
        runtime_identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-4"
      }

      stub(System, :cmd, fn "xcrun",
                            [
                              "simctl",
                              "launch",
                              "8491E652-18FC-4C0F-8AFA-2AEAFC3D4FF1",
                              ^bundle_identifier,
                              ""
                            ] ->
        {"Unable to launch com.example.myapp", 1}
      end)

      # When
      result = Simulators.launch_app(bundle_identifier, device)

      # Then
      assert {:error, "Failed to launch app: Unable to launch com.example.myapp"} = result
    end
  end

  describe "stop_recording/1" do
    test "stops recording successfully" do
      # Given
      port = Port.open({:spawn, "sleep 10"}, [:binary])
      os_pid = 12_345

      stub(Port, :info, fn ^port, :os_pid ->
        {:os_pid, os_pid}
      end)

      stub(System, :cmd, fn "kill", ["-TERM", "-12345"] ->
        {"", 0}
      end)

      stub(Port, :close, fn ^port ->
        true
      end)

      # When
      result = Simulators.stop_recording(port)

      # Then
      assert result == :ok
    end
  end
end
