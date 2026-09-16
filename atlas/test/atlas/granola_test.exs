defmodule Atlas.GranolaTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Audit.Activity
  alias Atlas.Granola
  alias Atlas.Granola.Note
  alias Atlas.Granola.NoteIngestion
  alias Atlas.Repo

  describe "store_meeting_event/2" do
    test "creates a Granola meeting timeline event" do
      account = insert_account!(%{primary_domain: "acme.example"})
      note = note()

      assert {:ok, %Event{} = event} =
               Granola.store_meeting_event(note, %{
                 "account_id" => account.id,
                 "title" => "Renewal planning",
                 "summary" => "Maya wants a renewal plan.",
                 "matched_on" => %{"type" => "primary_domain", "value" => "acme.example"}
               })

      assert event.account_id == account.id
      assert event.source == "granola"
      assert event.kind == "meeting"
      assert event.external_id == "not_renewal"
      assert event.title == "Renewal planning"
      assert event.body == "## Renewal\n\n- Maya wants a renewal plan."
      assert event.occurred_at == ~U[2026-05-07 13:30:00Z]
      assert event.url == "https://library/notes.granola.ai/d/renewal"
      assert event.metadata["summary"] == "Maya wants a renewal plan."
      assert event.metadata["summary_markdown"] == "## Renewal\n\n- Maya wants a renewal plan."
      assert event.metadata["matched_on"] == %{"type" => "primary_domain", "value" => "acme.example"}
      assert [%{"email" => "maya@acme.example"}] = event.metadata["attendees"]

      activity = Repo.get_by!(Activity, action: "account_event.synced_from_granola", target_id: event.id)
      assert activity.metadata["path"] == "/commercial/sales/accounts/#{account.id}"
    end

    test "updates the existing event when Granola edits the note" do
      account = insert_account!(%{primary_domain: "acme.example"})
      note = note(%{"summary_markdown" => "## Original"})

      assert {:ok, first} =
               Granola.store_meeting_event(note, %{
                 "account_id" => account.id,
                 "title" => "Original",
                 "summary" => "Original"
               })

      updated_note = note(%{"summary_markdown" => "## Updated\n\n- Budget approved."})

      assert {:ok, second} =
               Granola.store_meeting_event(updated_note, %{
                 "account_id" => account.id,
                 "title" => "Updated",
                 "summary" => "Updated"
               })

      assert first.id == second.id

      event = Repo.get!(Event, first.id)
      assert event.title == "Updated"
      assert event.body == "## Updated\n\n- Budget approved."

      activities =
        Repo.all(Activity)
        |> Enum.filter(&(&1.action == "account_event.synced_from_granola" and &1.target_id == event.id))

      assert length(activities) == 2
    end
  end

  describe "ingest_note/2" do
    test "returns the captured account event from the agent result" do
      account = insert_account!(%{primary_domain: "acme.example"})
      note = note()

      run_agent = fn ^note ->
        {:ok, event} =
          Granola.store_meeting_event(note, %{
            "account_id" => account.id,
            "title" => "Renewal planning",
            "summary" => "Maya wants a renewal plan."
          })

        {:ok, %{status: "captured", event_id: event.id, account_id: event.account_id}}
      end

      assert {:ok, %Event{} = event} = Granola.ingest_note(note, run_agent: run_agent)
      assert event.source == "granola"
      assert event.kind == "meeting"

      ingestion = Repo.get_by!(NoteIngestion, external_id: note.id)
      assert ingestion.status == "captured"
      assert ingestion.account_event_id == event.id
      assert ingestion.note_updated_at == note.updated_at
    end

    test "returns the stored event when the agent echoes a malformed event id" do
      account = insert_account!(%{primary_domain: "acme.example"})
      note = note()

      run_agent = fn ^note ->
        {:ok, event} =
          Granola.store_meeting_event(note, %{
            "account_id" => account.id,
            "title" => "Renewal planning",
            "summary" => "Maya wants a renewal plan."
          })

        {:ok, %{status: "captured", event_id: String.slice(event.id, 0, 35), account_id: event.account_id}}
      end

      assert {:ok, %Event{} = event} = Granola.ingest_note(note, run_agent: run_agent)
      assert event.id
      assert event.source == "granola"
      assert event.external_id == note.id
    end

    test "maps ignored agent results" do
      note = note()

      run_agent = fn ^note -> {:ok, %{status: "ignored", reason: "no_matching_account"}} end

      assert {:ignored, :no_matching_account} = Granola.ingest_note(note, run_agent: run_agent)

      ingestion = Repo.get_by!(NoteIngestion, external_id: note.id)
      assert ingestion.status == "ignored"
      assert ingestion.ignore_reason == "no_matching_account"
      assert ingestion.note_updated_at == note.updated_at
    end
  end

  describe "sync_notes/1" do
    test "fetches listed note details and routes them" do
      account = insert_account!(%{primary_domain: "acme.example"})
      note = note()

      list_notes = fn opts ->
        assert %DateTime{} = opts[:updated_after]
        {:ok, [%Note{id: note.id}]}
      end

      get_note = fn "not_renewal" -> {:ok, note} end

      run_agent = fn ^note ->
        {:ok, event} =
          Granola.store_meeting_event(note, %{
            "account_id" => account.id,
            "title" => "Renewal planning",
            "summary" => "Maya wants a renewal plan."
          })

        {:ok, %{status: "captured", event_id: event.id, account_id: event.account_id}}
      end

      assert {:ok, %{captured: 1, ignored: 0}} =
               Granola.sync_notes(list_notes: list_notes, get_note: get_note, run_agent: run_agent)
    end

    test "backfills notes without an updated_after boundary" do
      account = insert_account!(%{primary_domain: "acme.example"})
      note = note()

      list_notes = fn opts ->
        refute Keyword.has_key?(opts, :updated_after)
        {:ok, [%Note{id: note.id}]}
      end

      get_note = fn "not_renewal" -> {:ok, note} end

      run_agent = fn ^note ->
        {:ok, event} =
          Granola.store_meeting_event(note, %{
            "account_id" => account.id,
            "title" => "Renewal planning",
            "summary" => "Maya wants a renewal plan."
          })

        {:ok, %{status: "captured", event_id: event.id, account_id: event.account_id}}
      end

      assert {:ok, %{captured: 1, ignored: 0}} =
               Granola.backfill_notes(list_notes: list_notes, get_note: get_note, run_agent: run_agent)
    end

    test "skips a listed note when the stored event is already current" do
      account = insert_account!(%{primary_domain: "acme.example"})
      note = note()

      {:ok, _event} =
        Granola.store_meeting_event(note, %{
          "account_id" => account.id,
          "title" => "Renewal planning",
          "summary" => "Maya wants a renewal plan."
        })

      list_notes = fn _opts -> {:ok, [%Note{id: note.id, updated_at: note.updated_at}]} end
      get_note = fn _id -> flunk("current notes should not be fetched") end
      run_agent = fn _note -> flunk("current notes should not be routed") end

      assert {:ok, %{captured: 0, ignored: 0, skipped: 1}} =
               Granola.sync_notes(list_notes: list_notes, get_note: get_note, run_agent: run_agent)
    end

    test "skips a listed note when the stored ignored ingestion is already current" do
      note = note()

      assert {:ignored, :internal_meeting} =
               Granola.ingest_note(note,
                 run_agent: fn ^note -> {:ok, %{status: "ignored", reason: "internal_meeting"}} end
               )

      list_notes = fn _opts -> {:ok, [%Note{id: note.id, updated_at: note.updated_at}]} end
      get_note = fn _id -> flunk("current ignored notes should not be fetched") end
      run_agent = fn _note -> flunk("current ignored notes should not be routed") end

      assert {:ok, %{captured: 0, ignored: 0, skipped: 1}} =
               Granola.sync_notes(list_notes: list_notes, get_note: get_note, run_agent: run_agent)
    end
  end

  defp note(overrides \\ %{}) do
    %{
      "id" => "not_renewal",
      "object" => "note",
      "title" => "Renewal planning",
      "owner" => %{"name" => "Atlas User", "email" => "owner@tuist.dev"},
      "created_at" => "2026-05-07T13:00:00Z",
      "updated_at" => "2026-05-07T14:00:00Z",
      "web_url" => "https://library/notes.granola.ai/d/renewal",
      "calendar_event" => %{
        "event_title" => "Renewal planning",
        "organiser" => "owner@tuist.dev",
        "invitees" => [%{"email" => "maya@acme.example"}],
        "scheduled_start_time" => "2026-05-07T13:30:00Z",
        "scheduled_end_time" => "2026-05-07T14:00:00Z"
      },
      "attendees" => [%{"name" => "Maya Chen", "email" => "maya@acme.example"}],
      "summary_text" => "Maya wants a renewal plan.",
      "summary_markdown" => "## Renewal\n\n- Maya wants a renewal plan."
    }
    |> Map.merge(overrides)
    |> Note.from_api()
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Acme",
      segment: :customer
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
