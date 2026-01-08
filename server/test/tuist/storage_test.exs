defmodule Tuist.StorageTest do
  use ExUnit.Case, async: false
  use Mimic

  alias ExAws.Operation.S3
  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Storage

  setup do
    # Mock ExAws.Config.new to return a proper config that won't try to access instance metadata
    stub(ExAws.Config, :new, fn :s3 ->
      %{
        access_key_id: "test-access-key",
        secret_access_key: "test-secret-key",
        region: "auto",
        host: "fly.storage.tigris.dev",
        scheme: "https://",
        port: 443
      }
    end)

    # Mock Environment.decrypt_secrets to return an empty map
    stub(Environment, :decrypt_secrets, fn -> %{} end)
    :ok
  end

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
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      expect(ExAws.S3, :presigned_url, fn ^config,
                                          :put,
                                          ^bucket_name,
                                          ^object_key,
                                          [
                                            query_params: [
                                              {"partNumber", ^part_number},
                                              {"uploadId", ^upload_id}
                                            ],
                                            expires_in: ^expires_in
                                          ] ->
        {:ok, url}
      end)

      # When/Then
      assert Storage.multipart_generate_url(object_key, upload_id, part_number, :test, expires_in: expires_in) == url

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
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      expect(ExAws.S3, :presigned_url, fn ^config,
                                          :put,
                                          ^bucket_name,
                                          ^object_key,
                                          [
                                            query_params: [
                                              {"partNumber", ^part_number},
                                              {"uploadId", ^upload_id}
                                            ],
                                            expires_in: ^expires_in
                                          ] ->
        {:ok, url}
      end)

      # When/Then
      assert Storage.multipart_generate_url(object_key, upload_id, part_number, :test,
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
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :complete_multipart_upload, fn ^bucket_name, ^object_key, ^upload_id, ^parts ->
        operation
      end)

      expect(ExAws, :request!, fn ^operation, opts ->
        # Verify fast_api_req_opts are included
        assert Map.get(opts, :receive_timeout) == 5_000
        assert Map.get(opts, :pool_timeout) == 1_000
        assert Map.get(opts, :test) == :config
        :ok
      end)

      # When
      assert Storage.multipart_complete_upload(object_key, upload_id, parts, :test) == :ok

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
      expires_in = 60
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      expect(ExAws.S3, :presigned_url, fn ^config,
                                          :get,
                                          ^bucket_name,
                                          ^object_key,
                                          [
                                            query_params: [],
                                            expires_in: ^expires_in
                                          ] ->
        {:ok, url}
      end)

      # When
      assert Storage.generate_download_url(object_key, :test, expires_in: expires_in) == url

      # Then
      assert_received {^event_name, ^event_ref, %{}, %{object_key: ^object_key}}
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
      expires_in = 60
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      expect(ExAws.S3, :presigned_url, fn ^config,
                                          :put,
                                          ^bucket_name,
                                          ^object_key,
                                          [
                                            query_params: [],
                                            expires_in: ^expires_in
                                          ] ->
        {:ok, url}
      end)

      # When
      assert Storage.generate_upload_url(object_key, :test, expires_in: expires_in) == url

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
      object_key = UUIDv7.generate()
      url = "https://tuist.io/download-url"
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      expect(ExAws.S3, :download_file, fn ^bucket_name, ^object_key, :memory ->
        {:ok, url}
      end)

      stream = %Stream{}

      expect(ExAws, :stream!, fn _, ^config -> stream end)

      # When
      got = Storage.stream_object(object_key, :test)

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
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :head_object, fn ^bucket_name, ^object_key ->
        operation
      end)

      expect(ExAws, :request, fn ^operation, opts ->
        # Verify fast_api_req_opts are included
        assert Map.get(opts, :receive_timeout) == 5_000
        assert Map.get(opts, :pool_timeout) == 1_000
        assert Map.get(opts, :test) == :config
        {:ok, %{}}
      end)

      # When
      assert Storage.object_exists?(object_key, :test) == true

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
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :get_object, fn ^bucket_name, ^object_key ->
        operation
      end)

      expect(ExAws, :request, fn ^operation, opts ->
        # Verify fast_api_req_opts are included
        assert Map.get(opts, :receive_timeout) == 5_000
        assert Map.get(opts, :pool_timeout) == 1_000
        assert Map.get(opts, :test) == :config
        {:ok, %{body: content}}
      end)

      # When
      assert Storage.get_object_as_string(object_key, :test) == content

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
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :get_object, fn ^bucket_name, ^object_key ->
        operation
      end)

      expect(ExAws, :request, fn ^operation, opts ->
        # Verify fast_api_req_opts are included
        assert Map.get(opts, :receive_timeout) == 5_000
        assert Map.get(opts, :pool_timeout) == 1_000
        assert Map.get(opts, :test) == :config
        {:error, {:http_error, 404, %{}}}
      end)

      # When
      assert Storage.get_object_as_string(object_key, :test) == nil

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
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :initiate_multipart_upload, fn ^bucket_name, ^object_key ->
        operation
      end)

      expect(ExAws, :request!, fn ^operation, opts ->
        # Verify fast_api_req_opts are included
        assert Map.get(opts, :receive_timeout) == 5_000
        assert Map.get(opts, :pool_timeout) == 1_000
        assert Map.get(opts, :test) == :config
        %{body: %{upload_id: upload_id}}
      end)

      # When
      assert Storage.multipart_start(object_key, :test) == upload_id

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
      config = %{test: :config}

      stub(Environment, :s3_bucket_name, fn -> bucket_name end)
      stub(ExAws.Config, :new, fn :s3 -> config end)

      list_operation = %S3{body: UUIDv7.generate()}

      stub(ExAws.S3, :list_objects_v2, fn ^bucket_name, [prefix: ^project_slug, max_keys: _] ->
        list_operation
      end)

      stub(ExAws, :request!, fn ^list_operation, ^config ->
        %S3{body: %{contents: [%{}]}}
      end)

      stub(ExAws, :stream!, fn ^list_operation, ^config ->
        [%{key: object_key}] |> Stream.cycle() |> Stream.take(1)
      end)

      delete_operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :delete_all_objects, fn ^bucket_name, _ ->
        delete_operation
      end)

      expect(ExAws, :request, fn ^delete_operation, ^config -> {:ok, %{}} end)

      # When
      assert Storage.delete_all_objects(project_slug, :test) == :ok

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
      config = %{test: :config}

      stub(Environment, :s3_bucket_name, fn -> bucket_name end)
      stub(ExAws.Config, :new, fn :s3 -> config end)

      list_operation = %S3{body: UUIDv7.generate()}

      stub(ExAws.S3, :list_objects_v2, fn ^bucket_name, [prefix: ^project_slug, max_keys: _] ->
        list_operation
      end)

      stub(ExAws, :request!, fn ^list_operation, ^config ->
        %S3{body: %{contents: []}}
      end)

      # When
      assert Storage.delete_all_objects(project_slug, :test) == :ok

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
      config = %{test: :config}

      stub(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :head_object, fn ^bucket_name, ^object_key -> operation end)

      expect(ExAws, :request, fn ^operation, opts ->
        # Verify fast_api_req_opts are included
        assert Map.get(opts, :receive_timeout) == 5_000
        assert Map.get(opts, :pool_timeout) == 1_000
        assert Map.get(opts, :test) == :config
        {:ok, %{headers: %{"content-length" => ["#{size}"]}}}
      end)

      # When
      assert {:ok, ^size} = Storage.get_object_size(object_key, :test)

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration, size: size}, %{object_key: ^object_key}}

      assert is_number(size)
      assert is_number(duration)
    end
  end

  describe "put_object/3" do
    test "puts object without region headers for non-account actors" do
      # Given
      object_key = UUIDv7.generate()
      content = "test content"
      bucket_name = UUIDv7.generate()
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      operation = %S3{headers: %{}}

      expect(ExAws.S3, :put_object, fn ^bucket_name, ^object_key, ^content ->
        operation
      end)

      expect(ExAws, :request!, fn ^operation, _opts ->
        # Verify no region headers are added
        assert operation.headers == %{}
        :ok
      end)

      # When
      Storage.put_object(object_key, content, :test)
    end

    test "puts object with X-Tigris-Regions header for account with usa region" do
      # Given
      account = %Account{region: :usa}
      object_key = UUIDv7.generate()
      content = "test content"
      bucket_name = UUIDv7.generate()
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      operation = %S3{headers: %{}}

      expect(ExAws.S3, :put_object, fn ^bucket_name, ^object_key, ^content ->
        operation
      end)

      expect(ExAws, :request!, fn updated_operation, _opts ->
        # Verify region header is added
        assert updated_operation.headers == %{"X-Tigris-Regions" => "usa"}
        :ok
      end)

      # When
      Storage.put_object(object_key, content, account)
    end

    test "puts object without region headers for account with all region" do
      # Given
      account = %Account{region: :all}
      object_key = UUIDv7.generate()
      content = "test content"
      bucket_name = UUIDv7.generate()
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      operation = %S3{headers: %{}}

      expect(ExAws.S3, :put_object, fn ^bucket_name, ^object_key, ^content ->
        operation
      end)

      expect(ExAws, :request!, fn ^operation, _opts ->
        # Verify no region headers are added
        assert operation.headers == %{}
        :ok
      end)

      # When
      Storage.put_object(object_key, content, account)
    end
  end

  describe "multipart_start/2 with region support" do
    test "starts multipart upload with X-Tigris-Regions header for account with europe region" do
      # Given
      account = %Account{region: :europe}
      event_name = Tuist.Telemetry.event_name_storage_multipart_start_upload()
      event_ref = :telemetry_test.attach_event_handlers(self(), [event_name])

      upload_id = UUIDv7.generate()
      object_key = UUIDv7.generate()
      bucket_name = UUIDv7.generate()
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      operation = %S3{headers: %{}}

      expect(ExAws.S3, :initiate_multipart_upload, fn ^bucket_name, ^object_key ->
        operation
      end)

      expect(ExAws, :request!, fn updated_operation, _opts ->
        # Verify region header is added
        assert updated_operation.headers == %{"X-Tigris-Regions" => "eur"}
        %{body: %{upload_id: upload_id}}
      end)

      # When
      assert Storage.multipart_start(object_key, account) == upload_id

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration}, %{object_key: ^object_key}}
      assert is_number(duration)
    end

    test "starts multipart upload with X-Tigris-Regions header for account with usa region" do
      # Given
      account = %Account{region: :usa}
      event_name = Tuist.Telemetry.event_name_storage_multipart_start_upload()
      event_ref = :telemetry_test.attach_event_handlers(self(), [event_name])

      upload_id = UUIDv7.generate()
      object_key = UUIDv7.generate()
      bucket_name = UUIDv7.generate()
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      operation = %S3{headers: %{}}

      expect(ExAws.S3, :initiate_multipart_upload, fn ^bucket_name, ^object_key ->
        operation
      end)

      expect(ExAws, :request!, fn updated_operation, _opts ->
        # Verify region header is added
        assert updated_operation.headers == %{"X-Tigris-Regions" => "usa"}
        %{body: %{upload_id: upload_id}}
      end)

      # When
      assert Storage.multipart_start(object_key, account) == upload_id

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration}, %{object_key: ^object_key}}
      assert is_number(duration)
    end

    test "starts multipart upload without region headers for account with all region" do
      # Given
      account = %Account{region: :all}
      event_name = Tuist.Telemetry.event_name_storage_multipart_start_upload()
      event_ref = :telemetry_test.attach_event_handlers(self(), [event_name])

      upload_id = UUIDv7.generate()
      object_key = UUIDv7.generate()
      bucket_name = UUIDv7.generate()
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      operation = %S3{headers: %{}}

      expect(ExAws.S3, :initiate_multipart_upload, fn ^bucket_name, ^object_key ->
        operation
      end)

      expect(ExAws, :request!, fn ^operation, _opts ->
        # Verify no region headers are added
        assert operation.headers == %{}
        %{body: %{upload_id: upload_id}}
      end)

      # When
      assert Storage.multipart_start(object_key, account) == upload_id

      # Then
      assert_received {^event_name, ^event_ref, %{duration: duration}, %{object_key: ^object_key}}
      assert is_number(duration)
    end
  end

  describe "custom S3 storage" do
    test "uses custom S3 config when account has custom storage configured" do
      # Given
      account = %Account{
        s3_bucket_name: "custom-bucket",
        s3_access_key_id: "CUSTOM_ACCESS_KEY",
        s3_secret_access_key: "CUSTOM_SECRET_KEY",
        s3_region: "eu-west-1"
      }

      url = "https://custom-bucket.s3.eu-west-1.amazonaws.com/test-key"
      object_key = UUIDv7.generate()

      expect(ExAws.S3, :presigned_url, fn config, :get, "custom-bucket", ^object_key, _opts ->
        assert config.access_key_id == "CUSTOM_ACCESS_KEY"
        assert config.secret_access_key == "CUSTOM_SECRET_KEY"
        assert config.region == "eu-west-1"
        {:ok, url}
      end)

      # When
      result = Storage.generate_download_url(object_key, account)

      # Then
      assert result == url
    end

    test "uses custom S3 config with custom endpoint" do
      # Given
      account = %Account{
        s3_bucket_name: "custom-bucket",
        s3_access_key_id: "CUSTOM_ACCESS_KEY",
        s3_secret_access_key: "CUSTOM_SECRET_KEY",
        s3_endpoint: "https://minio.example.com:9000"
      }

      url = "https://minio.example.com:9000/custom-bucket/test-key"
      object_key = UUIDv7.generate()

      expect(ExAws.S3, :presigned_url, fn config, :get, "custom-bucket", ^object_key, _opts ->
        assert config.access_key_id == "CUSTOM_ACCESS_KEY"
        assert config.secret_access_key == "CUSTOM_SECRET_KEY"
        assert config.region == "us-east-1"
        assert config.scheme == "https://"
        assert config.host == "minio.example.com"
        assert config.port == 9000
        {:ok, url}
      end)

      # When
      result = Storage.generate_download_url(object_key, account)

      # Then
      assert result == url
    end

    test "uses default region when custom storage has no region configured" do
      # Given
      account = %Account{
        s3_bucket_name: "custom-bucket",
        s3_access_key_id: "CUSTOM_ACCESS_KEY",
        s3_secret_access_key: "CUSTOM_SECRET_KEY",
        s3_region: nil
      }

      url = "https://custom-bucket.s3.amazonaws.com/test-key"
      object_key = UUIDv7.generate()

      expect(ExAws.S3, :presigned_url, fn config, :get, "custom-bucket", ^object_key, _opts ->
        assert config.region == "us-east-1"
        {:ok, url}
      end)

      # When
      result = Storage.generate_download_url(object_key, account)

      # Then
      assert result == url
    end

    test "does not use custom storage when only bucket_name is set" do
      # Given
      account = %Account{
        s3_bucket_name: "custom-bucket",
        s3_access_key_id: nil,
        s3_secret_access_key: nil
      }

      url = "https://default-bucket.s3.amazonaws.com/test-key"
      object_key = UUIDv7.generate()
      bucket_name = UUIDv7.generate()
      config = %{test: :config}

      expect(Environment, :s3_bucket_name, fn -> bucket_name end)
      expect(ExAws.Config, :new, fn :s3 -> config end)

      expect(ExAws.S3, :presigned_url, fn ^config, :get, ^bucket_name, ^object_key, _opts ->
        {:ok, url}
      end)

      # When
      result = Storage.generate_download_url(object_key, account)

      # Then
      assert result == url
    end

    test "does not add Tigris region headers for custom S3 storage" do
      # Given
      account = %Account{
        s3_bucket_name: "custom-bucket",
        s3_access_key_id: "CUSTOM_ACCESS_KEY",
        s3_secret_access_key: "CUSTOM_SECRET_KEY",
        region: :europe
      }

      object_key = UUIDv7.generate()
      content = "test content"

      operation = %S3{headers: %{}}

      expect(ExAws.S3, :put_object, fn "custom-bucket", ^object_key, ^content ->
        operation
      end)

      expect(ExAws, :request!, fn updated_operation, _opts ->
        assert updated_operation.headers == %{}
        :ok
      end)

      # When
      Storage.put_object(object_key, content, account)
    end

    test "multipart_start does not add Tigris headers for custom S3 storage" do
      # Given
      account = %Account{
        s3_bucket_name: "custom-bucket",
        s3_access_key_id: "CUSTOM_ACCESS_KEY",
        s3_secret_access_key: "CUSTOM_SECRET_KEY",
        region: :usa
      }

      upload_id = UUIDv7.generate()
      object_key = UUIDv7.generate()

      operation = %S3{headers: %{}}

      expect(ExAws.S3, :initiate_multipart_upload, fn "custom-bucket", ^object_key ->
        operation
      end)

      expect(ExAws, :request!, fn updated_operation, _opts ->
        assert updated_operation.headers == %{}
        %{body: %{upload_id: upload_id}}
      end)

      # When
      result = Storage.multipart_start(object_key, account)

      # Then
      assert result == upload_id
    end

    test "object_exists? uses custom S3 config" do
      # Given
      account = %Account{
        s3_bucket_name: "custom-bucket",
        s3_access_key_id: "CUSTOM_ACCESS_KEY",
        s3_secret_access_key: "CUSTOM_SECRET_KEY",
        s3_region: "ap-southeast-1"
      }

      object_key = UUIDv7.generate()
      operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :head_object, fn "custom-bucket", ^object_key ->
        operation
      end)

      expect(ExAws, :request, fn ^operation, config ->
        assert config.access_key_id == "CUSTOM_ACCESS_KEY"
        assert config.secret_access_key == "CUSTOM_SECRET_KEY"
        assert config.region == "ap-southeast-1"
        {:ok, %{}}
      end)

      # When
      result = Storage.object_exists?(object_key, account)

      # Then
      assert result == true
    end

    test "delete_all_objects uses custom S3 config" do
      # Given
      account = %Account{
        s3_bucket_name: "custom-bucket",
        s3_access_key_id: "CUSTOM_ACCESS_KEY",
        s3_secret_access_key: "CUSTOM_SECRET_KEY"
      }

      prefix = UUIDv7.generate()
      object_key = UUIDv7.generate()
      list_operation = %S3{body: UUIDv7.generate()}

      stub(ExAws.S3, :list_objects_v2, fn "custom-bucket", [prefix: ^prefix, max_keys: _] ->
        list_operation
      end)

      stub(ExAws, :request!, fn ^list_operation, config ->
        assert config.access_key_id == "CUSTOM_ACCESS_KEY"
        %S3{body: %{contents: [%{}]}}
      end)

      stub(ExAws, :stream!, fn ^list_operation, config ->
        assert config.access_key_id == "CUSTOM_ACCESS_KEY"
        [%{key: object_key}] |> Stream.cycle() |> Stream.take(1)
      end)

      delete_operation = %S3{body: UUIDv7.generate()}

      expect(ExAws.S3, :delete_all_objects, fn "custom-bucket", _ ->
        delete_operation
      end)

      expect(ExAws, :request, fn ^delete_operation, config ->
        assert config.access_key_id == "CUSTOM_ACCESS_KEY"
        {:ok, %{}}
      end)

      # When
      result = Storage.delete_all_objects(prefix, account)

      # Then
      assert result == :ok
    end

    test "custom S3 storage takes precedence over default Tigris storage" do
      # Given
      account = %Account{
        s3_bucket_name: "custom-bucket",
        s3_access_key_id: "CUSTOM_ACCESS_KEY",
        s3_secret_access_key: "CUSTOM_SECRET_KEY"
      }

      url = "https://custom-bucket.s3.amazonaws.com/test-key"
      object_key = UUIDv7.generate()

      expect(ExAws.S3, :presigned_url, fn config, :get, "custom-bucket", ^object_key, _opts ->
        assert config.access_key_id == "CUSTOM_ACCESS_KEY"
        {:ok, url}
      end)

      # When
      result = Storage.generate_download_url(object_key, account)

      # Then
      assert result == url
    end
  end
end
