defmodule Tuist.Threads.AttachmentsTest do
  use ExUnit.Case, async: true

  alias Tuist.Threads.Attachments
  alias Tuist.Threads.Message

  defmodule Files do
    @moduledoc false
    def init(opts), do: {:ok, opts}
    def shutdown(_), do: :ok

    def write_file(opts, path, bytes) do
      send(opts[:test], {:file, path, bytes})
      opts[:result] || :ok
    end
  end

  test "validates both encoded and actual decoded bounds" do
    exact = file(:binary.copy(<<0>>, 1_048_576))
    assert {:ok, [^exact]} = Attachments.validate([exact])
    # Both have the same encoded length; the decoded bound must still reject it.
    over = file(:binary.copy(<<0>>, 1_048_577))
    assert byte_size(over["data_base64"]) == byte_size(exact["data_base64"])
    assert {:error, :invalid_arguments} = Attachments.validate([over])
    assert {:ok, _} = Attachments.validate(List.duplicate(file("a"), 4))
    assert {:error, :invalid_arguments} = Attachments.validate(List.duplicate(file("a"), 5))
    assert {:error, :invalid_arguments} = Attachments.validate([file("")])
  end

  test "rejects invalid metadata and base64 without raising" do
    valid = file("hello")

    for invalid <- [
          %{},
          nil,
          1,
          %{valid | "name" => "../secret"},
          %{valid | "name" => "a\\b"},
          %{valid | "name" => <<255>>},
          %{valid | "name" => ""},
          %{valid | "name" => "a\n.txt"},
          %{valid | "name" => String.duplicate("a", 256)},
          %{valid | "mime_type" => "invalid"},
          %{valid | "mime_type" => "text/plain\n"},
          %{valid | "data_base64" => "!!!!"},
          %{valid | "data_base64" => 1}
        ] do
      assert {:error, :invalid_arguments} = Attachments.validate([invalid])
    end

    assert {:error, :invalid_arguments} = Attachments.validate(%{})
    assert {:ok, []} = Attachments.validate(nil)
  end

  test "compaction retains only the latest prompt's images through tool rounds" do
    old = Condukt.Message.user("old metadata", [%{data: "old"}])
    current = Condukt.Message.user("current", [%{data: "current"}])
    tool = Condukt.Message.tool_result("id", "result")
    assert {:ok, [pruned, ^current, ^tool]} = Attachments.compact([old, current, tool], [])
    assert pruned.content == "old metadata"
    assert pruned.images == []
    next = Condukt.Message.user("no files")
    assert {:ok, messages} = Attachments.compact([old, current, tool, next], [])
    assert Enum.all?(messages, &(&1.images == []))
  end

  test "materializes binary and document bytes through the sandbox and exposes only image parts" do
    image = %{file("png") | "mime_type" => "image/png", "name" => "screen.png"}
    pdf = %{file("%PDF-1.7") | "mime_type" => "application/pdf", "name" => "doc.pdf"}
    binary = file(<<0, 255>>)
    message = %Message{id: Ecto.UUID.generate(), attachments: [image, pdf, binary]}
    assert {:ok, manifest} = Attachments.materialize([message], {Files, test: self()})
    assert manifest =~ "doc.pdf"
    assert manifest =~ "application/pdf"

    for {bytes, index} <- Enum.with_index(["png", "%PDF-1.7", <<0, 255>>]) do
      path = ".tuist-attachment-#{message.id}-#{index}"
      assert_receive {:file, ^path, ^bytes}
      assert manifest =~ path
    end

    assert [%{type: :base64, media_type: "image/png", data: data}] = Attachments.images([message])
    assert Base.decode64!(data) == "png"
    assert {:error, :attachment_workspace_unavailable} = Attachments.materialize([message], nil)
    assert {:error, :offline} = Attachments.materialize([message], {Files, test: self(), result: {:error, :offline}})
    assert {:ok, ""} = Attachments.materialize([], nil)
  end

  defp file(bytes),
    do: %{"name" => "input.bin", "mime_type" => "application/octet-stream", "data_base64" => Base.encode64(bytes)}
end
