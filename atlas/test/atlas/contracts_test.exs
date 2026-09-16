defmodule Atlas.ContractsTest do
  use ExUnit.Case, async: true

  alias Atlas.Contracts
  alias Atlas.Contracts.Template

  describe "list_template_sets/0" do
    test "includes the current 2026-02 set" do
      assert "2026-02" in Contracts.list_template_sets()
    end
  end

  describe "list_templates/1" do
    test "returns the six expected templates for the current set" do
      templates = Contracts.list_templates()

      filenames = templates |> Enum.map(& &1.filename) |> Enum.sort()

      assert filenames == [
               "annex-2-dpa.docx",
               "annex-3-daa.docx",
               "annex-4-sla.docx",
               "msa.docx",
               "order-form-self-hosted.docx",
               "order-form-tuist-hosted.docx"
             ]

      kinds_by_filename = Map.new(templates, &{&1.filename, &1.kind})

      assert kinds_by_filename["msa.docx"] == :msa
      assert kinds_by_filename["annex-2-dpa.docx"] == :annex_dpa
      assert kinds_by_filename["annex-3-daa.docx"] == :annex_daa
      assert kinds_by_filename["annex-4-sla.docx"] == :annex_sla
      assert kinds_by_filename["order-form-tuist-hosted.docx"] == :order_form_tuist_hosted
      assert kinds_by_filename["order-form-self-hosted.docx"] == :order_form_self_hosted

      assert Enum.all?(templates, &(&1.byte_size > 0))
      assert Enum.all?(templates, &(&1.template_set == "2026-02"))
    end

    test "returns an empty list for an unknown set" do
      assert Contracts.list_templates("does-not-exist") == []
    end
  end

  describe "fetch_template/2" do
    test "returns the template when present" do
      assert {:ok, %Template{filename: "msa.docx", kind: :msa}} =
               Contracts.fetch_template("2026-02", "msa.docx")
    end

    test "returns :not_found for unknown filenames" do
      assert {:error, :not_found} = Contracts.fetch_template("2026-02", "not-a-template.docx")
    end

    test "rejects path traversal attempts" do
      assert {:error, :not_found} = Contracts.fetch_template("2026-02", "../msa.docx")
      assert {:error, :not_found} = Contracts.fetch_template("2026-02", "../../etc/passwd")
      assert {:error, :not_found} = Contracts.fetch_template("2026-02", ".hidden.docx")
    end
  end

  describe "template_path/1" do
    test "resolves to the on-disk path" do
      {:ok, template} = Contracts.fetch_template("2026-02", "msa.docx")
      path = Contracts.template_path(template)

      assert File.exists?(path)
      assert String.ends_with?(path, "priv/contracts/templates/2026-02/msa.docx")
    end
  end

  describe "sign_download_token/1 + verify_download_token/1" do
    test "keeps download tokens valid for 24 hours" do
      assert Contracts.download_max_age() == 86_400
    end

    test "round-trips a template" do
      {:ok, template} = Contracts.fetch_template("2026-02", "msa.docx")
      token = Contracts.sign_download_token(template)

      assert {:ok, %{"template_set" => "2026-02", "filename" => "msa.docx"}} =
               Contracts.verify_download_token(token)
    end

    test "rejects a tampered token" do
      {:ok, template} = Contracts.fetch_template("2026-02", "msa.docx")
      token = Contracts.sign_download_token(template)
      tampered = String.replace(token, ~r/^./, "x")

      assert {:error, _reason} = Contracts.verify_download_token(tampered)
    end

    test "rejects missing or empty tokens" do
      assert {:error, :missing} = Contracts.verify_download_token(nil)
      assert {:error, :missing} = Contracts.verify_download_token(123)
    end
  end

  describe "download_url/1" do
    test "produces a URL with a token query param" do
      {:ok, template} = Contracts.fetch_template("2026-02", "msa.docx")
      url = Contracts.download_url(template)

      assert url =~ "/contracts/templates/2026-02/msa.docx?token="
    end
  end
end
