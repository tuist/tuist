defmodule Atlas.Accounts.Workers.ExtractDocumentServiceLevelsTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Accounts
  alias Atlas.Accounts.Workers.ExtractDocumentServiceLevels

  setup :verify_on_exit!

  describe "perform/1" do
    test "returns :ok when extraction succeeds" do
      expect(Accounts, :extract_document_service_levels, fn document_id ->
        assert document_id == "document-123"
        {:ok, %{status: :completed}}
      end)

      assert :ok = ExtractDocumentServiceLevels.perform(%Oban.Job{args: %{"document_id" => "document-123"}})
    end

    test "cancels when extraction returns a non-retryable reason" do
      for reason <- [
            :document_not_found,
            :account_not_found,
            :document_not_ready,
            :document_has_no_pages,
            :llm_not_configured
          ] do
        document_id = "document-#{reason}"

        expect(Accounts, :extract_document_service_levels, fn ^document_id -> {:error, reason} end)

        assert {:cancel, ^reason} =
                 ExtractDocumentServiceLevels.perform(%Oban.Job{args: %{"document_id" => document_id}})
      end
    end

    test "returns wrapped extraction errors as retryable errors" do
      expect(Accounts, :extract_document_service_levels, fn "document-123" ->
        {:error, %{reason: :provider_timeout}}
      end)

      assert {:error, :provider_timeout} =
               ExtractDocumentServiceLevels.perform(%Oban.Job{args: %{"document_id" => "document-123"}})
    end

    test "returns raw extraction errors as retryable errors" do
      expect(Accounts, :extract_document_service_levels, fn "document-123" -> {:error, :timeout} end)

      assert {:error, :timeout} =
               ExtractDocumentServiceLevels.perform(%Oban.Job{args: %{"document_id" => "document-123"}})
    end
  end
end
