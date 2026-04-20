defmodule Tuist.Runners.OrchardWorkerProvisionerTest do
  use ExUnit.Case, async: true

  alias Tuist.Runners.OrchardWorkerProvisioner

  describe "encode_kcpassword/1" do
    test "matches the macOS kcpassword XOR cipher for the builder's live password" do
      expected =
        <<0x45, 0xB1, 0x65, 0x68, 0xBD, 0x84, 0xAE, 0x9F, 0xD6, 0xEB, 0x59, 0x37, 0x89, 0x52, 0x23, 0xD2, 0xBC, 0xDD,
          0xEA, 0xA3, 0xB9, 0x1F, 0x7D, 0x89>>

      assert OrchardWorkerProvisioner.encode_kcpassword("887Ko8suuRFJ") == expected
    end

    test "pads shorter passwords up to 12 bytes" do
      encoded = OrchardWorkerProvisioner.encode_kcpassword("abc")
      assert byte_size(encoded) == 12
    end

    test "pads passwords of length divisible by 12 to the next multiple of 12" do
      encoded = OrchardWorkerProvisioner.encode_kcpassword(String.duplicate("a", 12))
      assert byte_size(encoded) == 24
    end
  end
end
