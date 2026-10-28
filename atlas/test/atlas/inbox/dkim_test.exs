defmodule Atlas.Inbox.DkimTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Inbox.Dkim
  alias Atlas.Inbox.Dkim.Resolver

  setup :verify_on_exit!

  describe "verified_domains/1" do
    test "returns the signing domain for a valid relaxed/relaxed signature" do
      %{raw: raw, spki_der: der} = signed_email("relaxed/relaxed")

      expect(Resolver, :public_keys, fn "test", "example.com" ->
        [%{key_type: :rsa, der: der}]
      end)

      assert Dkim.verified_domains(raw) == ["example.com"]
    end

    test "returns the signing domain for a valid simple/simple signature" do
      %{raw: raw, spki_der: der} = signed_email("simple/simple")

      stub(Resolver, :public_keys, fn "test", "example.com" ->
        [%{key_type: :rsa, der: der}]
      end)

      assert Dkim.verified_domains(raw) == ["example.com"]
    end

    test "returns [] when the body is tampered after signing" do
      %{raw: raw, spki_der: der} = signed_email("relaxed/relaxed")
      tampered = String.replace(raw, "hello world", "tampered body")

      stub(Resolver, :public_keys, fn _s, _d -> [%{key_type: :rsa, der: der}] end)

      assert Dkim.verified_domains(tampered) == []
    end

    test "returns [] when a header covered by the signature is altered" do
      %{raw: raw, spki_der: der} = signed_email("relaxed/relaxed")
      tampered = String.replace(raw, "To:inbox@atlas.tuist.dev", "To:attacker@evil.example")

      stub(Resolver, :public_keys, fn _s, _d -> [%{key_type: :rsa, der: der}] end)

      assert Dkim.verified_domains(tampered) == []
    end

    test "returns [] when no public key is published" do
      %{raw: raw} = signed_email("relaxed/relaxed")

      stub(Resolver, :public_keys, fn _s, _d -> [] end)

      assert Dkim.verified_domains(raw) == []
    end

    test "returns [] when there is no DKIM-Signature header" do
      raw = "From:alice@example.com\r\nTo:inbox@atlas.tuist.dev\r\n\r\nhello world\r\n"

      assert Dkim.verified_domains(raw) == []
    end

    test "skips signatures with an unsupported algorithm" do
      %{raw: raw, spki_der: der} = signed_email("relaxed/relaxed")
      mangled = String.replace(raw, "a=rsa-sha256", "a=rsa-magic256")

      stub(Resolver, :public_keys, fn _s, _d -> [%{key_type: :rsa, der: der}] end)

      assert Dkim.verified_domains(mangled) == []
    end
  end

  # Builds a real DKIM-signed message. The body hash and the signing input are
  # computed here independently (via :crypto / hand-derived canonical strings),
  # not by calling Dkim, so a verification pass exercises the module's own
  # canonicalization and assembly.
  defp signed_email(canon) do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})
    modulus = elem(private_key, 2)
    public_exponent = elem(private_key, 3)
    public_key = {:RSAPublicKey, modulus, public_exponent}

    {:SubjectPublicKeyInfo, spki_der, :not_encrypted} =
      :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)

    body = "hello world\r\n"
    bh = Base.encode64(:crypto.hash(:sha256, body))

    {from_line, to_line, dkim_signed} = canonical_lines(canon, bh)

    signing_input = from_line <> to_line <> dkim_signed
    signature = Base.encode64(:public_key.sign(signing_input, :sha256, private_key))

    dkim_header =
      "DKIM-Signature:v=1; a=rsa-sha256; c=#{canon}; d=example.com; s=test; " <>
        "h=from:to; bh=#{bh}; b=#{signature}"

    raw =
      Enum.join(["From:alice@example.com", "To:inbox@atlas.tuist.dev", dkim_header], "\r\n") <>
        "\r\n\r\n" <> body

    %{raw: raw, spki_der: spki_der}
  end

  defp canonical_lines("relaxed/relaxed", bh) do
    {
      "from:alice@example.com\r\n",
      "to:inbox@atlas.tuist.dev\r\n",
      "dkim-signature:v=1; a=rsa-sha256; c=relaxed/relaxed; d=example.com; s=test; " <>
        "h=from:to; bh=#{bh}; b="
    }
  end

  defp canonical_lines("simple/simple", bh) do
    {
      "From:alice@example.com\r\n",
      "To:inbox@atlas.tuist.dev\r\n",
      "DKIM-Signature:v=1; a=rsa-sha256; c=simple/simple; d=example.com; s=test; " <>
        "h=from:to; bh=#{bh}; b="
    }
  end
end
