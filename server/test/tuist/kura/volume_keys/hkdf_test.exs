defmodule Tuist.Kura.VolumeKeys.HKDFTest do
  use ExUnit.Case, async: true

  alias Tuist.Kura.VolumeKeys.HKDF

  test "matches RFC 5869 test case 1" do
    ikm = :binary.copy(<<0x0B>>, 22)
    salt = Base.decode16!("000102030405060708090A0B0C")
    info = Base.decode16!("F0F1F2F3F4F5F6F7F8F9")

    assert HKDF.extract(salt, ikm) ==
             Base.decode16!("077709362C2E32DF0DDC3F0DC47BBA6390B6C73BB50F9C3122EC844AD7C2B3E5")

    assert HKDF.derive(ikm, salt, info, 42) ==
             Base.decode16!("3CB25F25FAACD57A90434F64D0362F2A2D2D0A90CF1A5A4C5DB02D56ECC4C5BF34007208D5B887185865")
  end

  test "matches RFC 5869 test case 3, with an empty salt and info" do
    ikm = :binary.copy(<<0x0B>>, 22)

    assert HKDF.derive(ikm, "", "", 42) ==
             Base.decode16!("8DA4E775A563C18F715F802A063C5A31B8A11F5C5EE1879EC3454E5F3C738D2D9D201395FAA4B61A96C8")
  end
end
