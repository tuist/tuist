defmodule TuistWeb.LocalS3ControllerTest do
  use ExUnit.Case, async: true

  import SweetXml

  alias Tuist.Storage.LocalS3

  describe "XML parsing with SweetXml" do
    test "extracts object keys from delete XML" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Delete>
        <Object>
          <Key>file1.txt</Key>
        </Object>
        <Object>
          <Key>file2.txt</Key>
        </Object>
        <Object>
          <Key>path/to/file3.txt</Key>
        </Object>
      </Delete>
      """

      keys = xpath(xml, ~x"//Object/Key/text()"sl)

      assert keys == ["file1.txt", "file2.txt", "path/to/file3.txt"]
    end

    test "extracts parts from complete multipart XML" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <CompleteMultipartUpload>
        <Part>
          <PartNumber>1</PartNumber>
          <ETag>abc123</ETag>
        </Part>
        <Part>
          <PartNumber>2</PartNumber>
          <ETag>def456</ETag>
        </Part>
      </CompleteMultipartUpload>
      """

      parts =
        xml
        |> xpath(
          ~x"//Part"l,
          part_number: transform_by(~x"./PartNumber/text()"s, &String.to_integer/1),
          etag: ~x"./ETag/text()"s
        )
        |> Enum.map(fn %{part_number: part_number, etag: etag} ->
          {part_number, etag}
        end)

      assert parts == [{1, "abc123"}, {2, "def456"}]
    end

    test "extracts upload ID from initiate multipart response" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <InitiateMultipartUploadResult>
        <Bucket>test-bucket</Bucket>
        <Key>test-key</Key>
        <UploadId>abc123xyz</UploadId>
      </InitiateMultipartUploadResult>
      """

      upload_id = xpath(xml, ~x"//UploadId/text()"s)

      assert upload_id == "abc123xyz"
    end
  end

  describe "storage directory" do
    test "storage directories exist and are valid paths" do
      uploads_dir = LocalS3.uploads_directory()
      completed_dir = LocalS3.completed_directory()
      storage_dir = LocalS3.storage_directory()

      assert is_binary(uploads_dir)
      assert is_binary(completed_dir)
      assert is_binary(storage_dir)
      assert String.contains?(storage_dir, "tmp/local_s3_storage")
      assert String.contains?(uploads_dir, "uploads")
      assert String.contains?(completed_dir, "completed")
    end
  end
end
