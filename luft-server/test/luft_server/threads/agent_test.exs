defmodule LuftServer.Threads.AgentTest do
  use ExUnit.Case, async: true

  alias LuftServer.Threads.Agent
  alias LuftServer.Threads.AskUser
  alias LuftServer.Threads.Attachments

  test "final reply accepts legacy text and bounds distinct suggestions and icons" do
    assert {"legacy", [], %{}} = Agent.decode_reply("legacy")

    assert {"Hello", ["Explain", "Retry"], %{"Explain" => "explain"}} =
             Agent.decode_reply(
               Jason.encode!(%{
                 reply: " Hello ",
                 suggestions: [
                   %{text: " Explain ", icon: "explain"},
                   %{text: "Explain", icon: "test"},
                   %{text: "Retry", icon: "bad"},
                   String.duplicate("x", 121)
                 ]
               })
             )
  end

  test "transcript is bounded and encodes message text as untrusted JSON" do
    text =
      Agent.transcript(
        for n <- 1..45, do: %{kind: "human", body: "#{n}:" <> String.duplicate("x", 5000)}
      )

    refute text =~ "\"body\":\"1:"
    assert text =~ "\"body\":\"45:"
    assert byte_size(text) < 174_000

    # A saved prompt plus caller input may fill the entire accepted message.
    latest = String.duplicate("x", 15_990) <> "CHECK_TAIL"
    assert Agent.transcript([%{kind: "human", body: latest}]) =~ "CHECK_TAIL"
  end

  test "attachments reject traversal and compaction retains only latest user images" do
    file = %{
      "name" => "../secret",
      "mime_type" => "text/plain",
      "data_base64" => Base.encode64("text")
    }

    assert {:error, :invalid_arguments} = Attachments.validate([file])
    assert {:ok, [_]} = Attachments.validate([%{file | "name" => "safe.txt"}])

    assert {:error, :attachment_workspace_unavailable} =
             Attachments.materialize(
               [%{id: "id", attachments: [%{file | "name" => "safe.txt"}]}],
               nil
             )

    first =
      Condukt.Message.user("first", [%{type: :base64, media_type: "image/png", data: "a"}])

    last =
      Condukt.Message.user("last", [%{type: :base64, media_type: "image/png", data: "b"}])

    assert {:ok, [%{images: []}, ^last]} = Attachments.compact([first, last], [])
  end

  test "questions require distinct options and explicit other-answer permission" do
    args = %{
      "question" => "Which?",
      "options" => [%{"id" => "a", "label" => "A"}, %{"id" => "b", "label" => "B"}],
      "allow_other" => false
    }

    assert {:ok, ^args} = AskUser.validate(args)

    assert {:error, _} =
             AskUser.validate(%{args | "options" => [hd(args["options"]), hd(args["options"])]})

    assert {:error, _} = AskUser.validate(Map.delete(args, "allow_other"))
  end
end
