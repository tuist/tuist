defmodule Tuist.StorageTest do
  use ExUnit.Case, async: false
  use Mimic

  alias ExAws.Operation.S3
  alias Tuist.Environment
  alias Tuist.Storage

  describe "multipart_generate_url/4" do
    test "generates the URL using the ExAws.S3 module and reports the telemetry event" do
      # Given
      url = "https://tuist.io/upload-url"

      event_name =
        Tuist.Telemetry.event_name_storage_multipart_generate_upload_part_presigned_url()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      upload_id = UUIDv7.generate()
      object_key = UUIDv7.generate()
      part_number = 1
      expires_in = 30
      bucket_name = UUIDv7.generate()
      stub(ExAws.Config, :new, fn :s3 -> %{} end)
      expect(Environment, :s3_bucket_name, fn -> bucket_name end)

      expect(ExAws.S3, :presigned_url, fn _,
                                          :put,
                                          ^bucket_name,
                                          ^object_key,
                                          [
                                            query_params: [
                                              {"partNumber", ^part_number},
                                              {"uploadId", ^upload_id}
                                            ],
                                            headers: [],
                                            virtual_host: true,
                                            expires_in: ^expires_in
                                          ] ->
        {:ok, url}
      end)

      # When/Then
      assert Storage.multipart_generate_url(object_key, upload_id, part_number, expires_in: expires_in) == url

      assert_received {^event_name, ^event_ref, %{},
                       %{
                         object_key: ^object_key,
                         upload_id: ^upload_id,
                         part_number: ^part_number
                       }}
    end

    test "generates the URL using the ExAws.S3 module and reports the telemetry event when content_length is provided" do
      # Given
      url = "https://tuist.io/upload-url"

      event_name =
        Tuist.Telemetry.event_name_storage_multipart_generate_upload_part_presigned_url()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      upload_id = UUIDv7.generate()
      object_key = UUIDv7.generate()
      part_number = 1
      expires_in = 30
      bucket_name = UUIDv7.generate()
      stub(ExAws.Config, :new, fn :s3 -> %{} end)
      expect(Environment, :s3_bucket_name, fn -> bucket_name end)

      expect(ExAws.S3, :presigned_url, fn _,
                                          :put,
                                          ^bucket_name,
                                          ^object_key,
                                          [
                                            query_params: [
                                              {"partNumber", ^part_number},
                                              {"uploadId", ^upload_id}
                                            ],
                                            headers: [
                                              {"Content-Length", "300"}
                                            ],
                                            virtual_host: true,
                                            expires_in: ^expires_in
                                          ] ->
        {:ok, url}
      end)

      # When/Then
      assert Storage.multipart_generate_url(object_key, upload_id, part_number,
               expires_in: expires_in,
               content_length: 300
             ) == url

      assert_received {^event_name, ^event_ref, %{},
                       %{
                         object_key: ^object_key,
                         upload_id: ^upload_id,
                         part_number: ^part_number
                       }}
    end
  end

  describe "multipart_complete_upload/3" do
    test "completes the upload using the Ex.Aws module and sends the right telemetry event" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_multipart_complete_upload()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      bucket_name = UUIDv7.generate()
      upload_id = UUIDv7.generate()
      object_key = UUIDv7.generate()
      parts = [{1, "etag-1"}, {2, "etag-2"}]
      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :complete_multipart_upload, fn ^bucket_name, ^object_key, ^upload_id, ^parts ->
        operation
      end)

      expect(ExAws, :request!, fn ^operation -> :ok end)

      # When
      assert Storage.multipart_complete_upload(object_key, upload_id, parts) == :ok

      # Then
      parts_count = length(parts)

      assert_received {^event_name, ^event_ref, %{duration: duration, parts_count: ^parts_count},
                       %{object_key: ^object_key, upload_id: ^upload_id}}

      assert is_number(duration)
    end
  end

  describe "generate_download_url/2" do
    test "generates the download URL using the ExAws.S3 module and sends the right telemetry event" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_generate_download_presigned_url()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      url = "https://tuist.io/download-url"
      object_key = UUIDv7.generate()
      bucket_name = UUIDv7.generate()
      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expires_in = 60
      stub(ExAws.Config, :new, fn :s3 -> %{} end)

      expect(ExAws.S3, :presigned_url, fn _,
                                          :get,
                                          ^bucket_name,
                                          ^object_key,
                                          [
                                            query_params: [],
                                            expires_in: ^expires_in,
                                            virtual_host: true
                                          ] ->
        {:ok, url}
      end)

      # When
      assert Storage.generate_download_url(object_key, expires_in: expires_in) == url

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration}, %{object_key: ^object_key}}

      assert is_number(duration)
    end
  end

  describe "generate_upload_url/2" do
    test "generates the upload URL using the ExAws.S3 module and sends the right telemetry event" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_generate_upload_presigned_url()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      url = "https://tuist.io/upload-url"
      object_key = UUIDv7.generate()
      bucket_name = UUIDv7.generate()
      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expires_in = 60
      stub(ExAws.Config, :new, fn :s3 -> %{} end)

      expect(ExAws.S3, :presigned_url, fn _,
                                          :put,
                                          ^bucket_name,
                                          ^object_key,
                                          [
                                            query_params: [],
                                            expires_in: ^expires_in,
                                            virtual_host: true
                                          ] ->
        {:ok, url}
      end)

      # When
      assert Storage.generate_upload_url(object_key, expires_in: expires_in) == url

      # Then
      assert_received {^event_name, ^event_ref, %{}, %{object_key: ^object_key}}
    end
  end

  describe "stream_object/2" do
    test "streams object" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_stream_object()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      bucket_name = UUIDv7.generate()
      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      object_key = UUIDv7.generate()
      url = "https://tuist.io/download-url"

      expect(ExAws.S3, :download_file, fn ^bucket_name, ^object_key, :memory ->
        {:ok, url}
      end)

      stream = %Stream{}

      expect(ExAws, :stream!, fn _ -> stream end)

      # When
      got = Storage.stream_object(object_key)

      # Then
      assert got == stream
      assert_received {^event_name, ^event_ref, %{}, %{object_key: ^object_key}}
    end
  end

  describe "object_exists?/1" do
    test "generates the download URL using the ExAws.S3 module and sends the right telemetry event" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_check_object_existence()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      object_key = UUIDv7.generate()
      bucket_name = UUIDv7.generate()
      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :head_object, fn ^bucket_name, ^object_key ->
        operation
      end)

      expect(ExAws, :request, fn ^operation -> {:ok, %{}} end)

      # When
      assert Storage.object_exists?(object_key) == true

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration}, %{object_key: ^object_key}}

      assert is_number(duration)
    end
  end

  describe "get_object_as_string/1" do
    test "obtains the object using ExAws.S3 and sends the right telemetry event" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_get_object_as_string()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      content = UUIDv7.generate()
      object_key = UUIDv7.generate()
      bucket_name = UUIDv7.generate()
      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :get_object, fn ^bucket_name, ^object_key ->
        operation
      end)

      expect(ExAws, :request, fn ^operation -> {:ok, %{body: content}} end)

      # When
      assert Storage.get_object_as_string(object_key) == content

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration}, %{object_key: ^object_key}}

      assert is_number(duration)
    end

    test "returns nil if the object doesn't exist" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_get_object_as_string()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      object_key = UUIDv7.generate()
      bucket_name = UUIDv7.generate()
      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :get_object, fn ^bucket_name, ^object_key ->
        operation
      end)

      expect(ExAws, :request, fn ^operation -> {:error, {:http_error, 404, %{}}} end)

      # When
      assert Storage.get_object_as_string(object_key) == nil

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration}, %{object_key: ^object_key}}

      assert is_number(duration)
    end
  end

  describe "multipart_start/1" do
    test "starts the multipart upload using ExAws.S3 and sends the right telemetry event" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_multipart_start_upload()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      upload_id = UUIDv7.generate()
      object_key = UUIDv7.generate()
      bucket_name = UUIDv7.generate()
      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :initiate_multipart_upload, fn ^bucket_name, ^object_key ->
        operation
      end)

      expect(ExAws, :request!, fn ^operation -> %{body: %{upload_id: upload_id}} end)

      # When
      assert Storage.multipart_start(object_key) == upload_id

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration}, %{object_key: ^object_key}}

      assert is_number(duration)
    end
  end

  describe "delete_all_objects/1" do
    test "deletes all objects using ExAws.S3 and sends the right telemetry event" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_delete_all_objects()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      project_slug = UUIDv7.generate()
      bucket_name = UUIDv7.generate()
      object_key = UUIDv7.generate()

      stub(Environment, :s3_bucket_name, fn -> bucket_name end)
      list_operation = %S3{body: UUIDv7.generate()}

      stub(ExAws.S3, :list_objects_v2, fn ^bucket_name, [prefix: ^project_slug, max_keys: _] ->
        list_operation
      end)

      stub(ExAws, :request!, fn ^list_operation ->
        %S3{body: %{contents: [%{}]}}
      end)

      stub(ExAws, :stream!, fn ^list_operation ->
        [%{key: object_key}] |> Stream.cycle() |> Stream.take(1)
      end)

      delete_operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :delete_all_objects, fn ^bucket_name, _ ->
        delete_operation
      end)

      expect(ExAws, :request, fn ^delete_operation -> {:ok, %{}} end)

      # When
      assert Storage.delete_all_objects(project_slug) == :ok

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration}, %{}}

      assert is_number(duration)
    end

    test "skips deletion if no objects with a given prefix exist" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_delete_all_objects()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      project_slug = UUIDv7.generate()
      bucket_name = UUIDv7.generate()

      stub(Environment, :s3_bucket_name, fn -> bucket_name end)
      list_operation = %S3{body: UUIDv7.generate()}

      stub(ExAws.S3, :list_objects_v2, fn ^bucket_name, [prefix: ^project_slug, max_keys: _] ->
        list_operation
      end)

      stub(ExAws, :request!, fn ^list_operation ->
        %S3{body: %{contents: []}}
      end)

      # When
      assert Storage.delete_all_objects(project_slug) == :ok

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration}, %{}}

      assert is_number(duration)
    end
  end

  describe "get_object_size/1" do
    test "gets the size using ExAws.S3 and sends the right telemetry event" do
      # Given
      event_name =
        Tuist.Telemetry.event_name_storage_get_object_as_string_size()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [event_name])

      size = 25
      object_key = UUIDv7.generate()
      bucket_name = UUIDv7.generate()
      stub(Environment, :s3_bucket_name, fn -> bucket_name end)
      operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :head_object, fn ^bucket_name, ^object_key -> operation end)

      expect(ExAws, :request!, fn ^operation ->
        %{headers: %{"content-length" => ["#{size}"]}}
      end)

      # When
      assert Storage.get_object_size(object_key) == size

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration, size: size}, %{object_key: ^object_key}}

      assert is_number(size)
      assert is_number(duration)
    end
  end
end
