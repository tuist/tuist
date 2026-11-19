defmodule Tuist.Application.CertificateTrustTest do
  use ExUnit.Case, async: true

  alias Tuist.Application.CertificateTrust

  # Public certificates from #14511's incident controls. Keep the twelve-key
  # inventory self-contained: four issuer roots and eight intermediates.
  @fixtures Path.join(__DIR__, "fixtures")

  test "leaves the shared CA cache alone outside the macOS xcresult processor" do
    for mode <- [:web, :processor, :swift_registry_sync],
        os <- [{:unix, :darwin}, {:unix, :linux}] do
      assert :ok = CertificateTrust.configure!(mode, os)
    end

    assert :ok = CertificateTrust.configure!(:xcresult_processor, {:unix, :linux})
  end

  test "accepts unrelated public and private trust anchors in both certificate forms" do
    [public] = certificates("isrg-root-x1.pem")

    %{cert: private} =
      :public_key.pkix_test_root_cert(~c"Enterprise test CA", key: {:namedCurve, {1, 2, 840, 10_045, 3, 1, 7}})

    assert :ok = CertificateTrust.assert_clean!([public, private])
    assert :ok = CertificateTrust.assert_clean!([otp_certificate(public), otp_certificate(private)])
  end

  test "rejects an empty effective store" do
    assert_raise RuntimeError, ~r/empty CA store/, fn -> CertificateTrust.assert_clean!([]) end
  end

  test "rejects every incident key in mixed stores and both certificate forms" do
    [healthy] = certificates("isrg-root-x1.pem")
    blocked = certificates("issuer-roots.pem") ++ certificates("distrusted-intermediates.pem")
    assert length(blocked) == 12
    assert length(Enum.uniq(blocked)) == 12

    for der <- blocked, certificate <- [der, otp_certificate(der)] do
      assert_raise RuntimeError, ~r/distrusted CA SPKI [a-f0-9]{64}/, fn ->
        CertificateTrust.assert_clean!([healthy, certificate, healthy])
      end
    end
  end

  @tag :tmp_dir
  test "filters an unmodified image's bundle without losing public or private anchors", %{tmp_dir: tmp_dir} do
    [public] = certificates("isrg-root-x1.pem")

    %{cert: private} =
      :public_key.pkix_test_root_cert(~c"Enterprise test CA", key: {:namedCurve, {1, 2, 840, 10_045, 3, 1, 7}})

    blocked = certificates("issuer-roots.pem") ++ certificates("distrusted-intermediates.pem")
    source = Path.join(tmp_dir, "stock-image.pem")
    pem = :public_key.pem_encode(Enum.map([public, private | blocked], &{:Certificate, &1, :not_encrypted}))
    File.write!(source, pem)

    path = CertificateTrust.filtered_bundle!(source)
    on_exit(fn -> File.rm!(path) end)

    assert File.read!(source) == pem

    assert path |> File.read!() |> :public_key.pem_decode() ==
             [{:Certificate, public, :not_encrypted}, {:Certificate, private, :not_encrypted}]

    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
  end

  @tag :tmp_dir
  test "never creates an empty runtime trust store", %{tmp_dir: tmp_dir} do
    source = Path.join(tmp_dir, "empty.pem")

    for pem <- ["", File.read!(Path.join(@fixtures, "issuer-roots.pem")), "not a certificate"] do
      File.write!(source, pem)

      assert_raise RuntimeError, ~r/empty CA store/, fn ->
        CertificateTrust.filtered_bundle!(source)
      end
    end
  end

  @tag :tmp_dir
  test "loads the filtered bundle and can reload it in a fresh OTP VM", %{tmp_dir: tmp_dir} do
    [public] = certificates("isrg-root-x1.pem")
    source = Path.join(tmp_dir, "stock-image.pem")

    File.write!(
      source,
      File.read!(Path.join(@fixtures, "issuer-roots.pem")) <> File.read!(Path.join(@fixtures, "isrg-root-x1.pem"))
    )

    script = """
    alias Tuist.Application.CertificateTrust
    [source, destination] = System.argv()
    path = CertificateTrust.filtered_bundle!(source)
    try do
      Application.put_env(:public_key, :cacerts_path, path)
      :ok = CertificateTrust.configure!(:xcresult_processor, {:unix, :darwin})
      for _ <- 1..2 do
        [{:cert, der, _}] = :public_key.cacerts_get()
        File.write!(destination, der)
        :public_key.cacerts_clear()
      end
    after
      File.rm!(path)
    end
    """

    destination = Path.join(tmp_dir, "effective.der")
    module = Path.expand("../../../lib/tuist/application/certificate_trust.ex", __DIR__)

    assert {_, 0} =
             System.cmd(System.find_executable("elixir"), ["-r", module, "-e", script, "--", source, destination],
               stderr_to_stdout: true
             )

    assert File.read!(destination) == public
  end

  defp certificates(name) do
    for {:Certificate, der, :not_encrypted} <- @fixtures |> Path.join(name) |> File.read!() |> :public_key.pem_decode() do
      der
    end
  end

  defp otp_certificate(der), do: {:cert, der, :public_key.pkix_decode_cert(der, :otp)}
end
