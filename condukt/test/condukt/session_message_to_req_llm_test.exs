defmodule Condukt.SessionMessageToReqLLMTest do
  use ExUnit.Case, async: true

  alias Condukt.Message
  alias Condukt.Session
  alias ReqLLM.Message.ContentPart

  describe "message_to_req_llm/1 with user messages" do
    test "encodes a plain text message as a string-content user message" do
      msg = Message.user("hello")

      assert %ReqLLM.Message{role: :user} = req_msg = Session.message_to_req_llm(msg)
      # ReqLLM stores plain text as a single ContentPart inside a list, or as
      # a string depending on the constructor; assert it round-trips to "hello".
      assert message_text(req_msg) == "hello"
    end

    test "encodes attached images as ContentPart structs (not legacy tuples)" do
      image = %{type: :base64, media_type: "image/png", data: "QUJD"}
      msg = Message.user("describe this", [image])

      assert %ReqLLM.Message{role: :user, content: parts} = Session.message_to_req_llm(msg)
      assert is_list(parts)
      assert Enum.all?(parts, &match?(%ContentPart{}, &1))

      assert Enum.any?(parts, fn part ->
               part.type == :text and part.text == "describe this"
             end)

      assert Enum.any?(parts, fn part ->
               part.type == :image_url and
                 part.url == "data:image/png;base64,QUJD"
             end)
    end
  end

  describe "message_to_req_llm/1 with tool results" do
    test "encodes error tuples as text" do
      msg = Message.tool_result("call_1", {:error, :boom})

      assert %ReqLLM.Message{role: :tool} = req_msg = Session.message_to_req_llm(msg)
      assert message_text(req_msg) == "Error: :boom"
    end
  end

  defp message_text(%ReqLLM.Message{content: content}) when is_binary(content), do: content

  defp message_text(%ReqLLM.Message{content: parts}) when is_list(parts) do
    parts
    |> Enum.filter(&match?(%ContentPart{type: :text}, &1))
    |> Enum.map_join("", & &1.text)
  end
end
