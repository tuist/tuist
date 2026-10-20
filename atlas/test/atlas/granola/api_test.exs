defmodule Atlas.Granola.APITest do
  use ExUnit.Case, async: true

  alias Atlas.Granola.API
  alias Atlas.Granola.Note

  describe "list_notes/1" do
    test "fetches paginated notes" do
      request = fn %Req.Request{} = request ->
        assert URI.to_string(request.url) == "https://granola.example/v1/notes"
        assert request.options.auth == {:bearer, "grn_test"}
        assert request.options.receive_timeout == 12_000
        assert request.headers["accept"] == ["application/json"]

        case request.options.params[:cursor] do
          nil ->
            assert request.options.params[:updated_after] == "2026-05-01T00:00:00Z"

            {:ok,
             %Req.Response{
               status: 200,
               body: %{
                 "notes" => [
                   %{
                     "id" => "not_first",
                     "object" => "note",
                     "title" => "First meeting",
                     "created_at" => "2026-05-01T10:00:00Z",
                     "updated_at" => "2026-05-01T11:00:00Z"
                   }
                 ],
                 "hasMore" => true,
                 "cursor" => "next-page"
               }
             }}

          "next-page" ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{
                 "notes" => [
                   %{
                     "id" => "not_second",
                     "object" => "note",
                     "title" => "Second meeting",
                     "created_at" => "2026-05-02T10:00:00Z",
                     "updated_at" => "2026-05-02T11:00:00Z"
                   }
                 ],
                 "hasMore" => false,
                 "cursor" => nil
               }
             }}
        end
      end

      assert {:ok, [%Note{id: "not_first"}, %Note{id: "not_second"}]} =
               API.list_notes(
                 api_key: "grn_test",
                 base_url: "https://granola.example/v1",
                 receive_timeout: 12_000,
                 request: request,
                 updated_after: ~U[2026-05-01 00:00:00Z]
               )
    end

    test "returns :disabled without an API key" do
      assert :disabled = API.list_notes(api_key: nil)
    end
  end

  describe "get_note/2" do
    test "fetches and normalizes a note" do
      request = fn %Req.Request{} = request ->
        assert URI.to_string(request.url) == "https://granola.example/v1/notes/not_detail"
        assert request.options.params[:include] == "transcript"

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "id" => "not_detail",
             "object" => "note",
             "title" => "Renewal planning",
             "owner" => %{"name" => "Atlas User", "email" => "owner@tuist.dev"},
             "created_at" => "2026-05-07T13:00:00Z",
             "updated_at" => "2026-05-07T14:00:00Z",
             "web_url" => "https://notes.granola.ai/d/detail",
             "calendar_event" => %{
               "event_title" => "Renewal planning",
               "organiser" => "owner@tuist.dev",
               "invitees" => [%{"email" => "maya@acme.example"}],
               "scheduled_start_time" => "2026-05-07T13:30:00Z",
               "scheduled_end_time" => "2026-05-07T14:00:00Z"
             },
             "attendees" => [%{"name" => "Maya Chen", "email" => "MAYA@ACME.EXAMPLE"}],
             "summary_text" => "Maya wants a renewal plan.",
             "summary_markdown" => "## Renewal\n\nMaya wants a renewal plan.",
             "transcript" => [%{"text" => "Hello"}]
           }
         }}
      end

      assert {:ok, %Note{} = note} =
               API.get_note("not_detail",
                 api_key: "grn_test",
                 base_url: "https://granola.example/v1",
                 receive_timeout: 12_000,
                 request: request,
                 include: :transcript
               )

      assert note.title == "Renewal planning"
      assert note.attendees == [%{"email" => "maya@acme.example", "name" => "Maya Chen"}]
      assert note.created_at == ~U[2026-05-07 13:00:00Z]
      assert note.calendar_event["scheduled_start_time"] == "2026-05-07T13:30:00Z"
    end
  end
end
