defmodule Atlas.Accounts.Workers.ScheduleServiceLevelExtractionsTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Workers.ExtractDocumentServiceLevels
  alias Atlas.Accounts.Workers.ScheduleServiceLevelExtractions
  alias Atlas.Documents.Document

  setup :verify_on_exit!

  describe "ScheduleServiceLevelExtractions.perform/1" do
    test "returns zero when there are no candidate documents" do
      assert {:ok, 0} = perform_job(ScheduleServiceLevelExtractions, %{})
    end

    test "enqueues one extraction job per candidate document" do
      account = insert_account!(%{name: "Scheduler", segment: :customer})
      first = insert_document!(account, %{title: "First SLA"})
      second = insert_document!(account, %{title: "Second SLA"})

      assert {:ok, 2} = perform_job(ScheduleServiceLevelExtractions, %{})

      assert_enqueued(worker: ExtractDocumentServiceLevels, args: %{"document_id" => first.id})
      assert_enqueued(worker: ExtractDocumentServiceLevels, args: %{"document_id" => second.id})
    end

    test "stops scheduling when job insertion fails" do
      error_changeset =
        %Oban.Job{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:args, "is invalid")

      expect(Accounts, :list_service_level_candidate_document_ids, fn -> ["first", "second"] end)

      expect(Oban, :insert, 2, fn
        %Ecto.Changeset{changes: %{args: %{document_id: "first"}}} = changeset ->
          {:ok, Ecto.Changeset.apply_changes(changeset)}

        %Ecto.Changeset{changes: %{args: %{document_id: "second"}}} ->
          {:error, error_changeset}
      end)

      assert {:error, ^error_changeset} = ScheduleServiceLevelExtractions.perform(%Oban.Job{})
    end
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :customer
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_document!(account, attrs) do
    defaults = %{
      title: "Document",
      original_filename: "document.txt",
      content_type: "text/plain",
      byte_size: 10,
      checksum_sha256: "#{System.unique_integer([:positive])}",
      storage_bucket: "test-documents",
      storage_key: "documents/#{System.unique_integer([:positive])}.txt",
      status: "ready",
      source: "upload"
    }

    %Document{}
    |> Document.changeset(Map.merge(defaults, attrs))
    |> Ecto.Changeset.change(account_id: account.id)
    |> Repo.insert!()
  end
end
