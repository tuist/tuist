defmodule Tuist.Telemetry do
  @moduledoc false
  def event_name_http_queue_status do
    [:tuist, :http, :queue, :status]
  end

  def event_name_projects_count do
    [:tuist, :projects, :count]
  end

  def event_name_accounts_users_count do
    [:tuist, :accounts, :users, :count]
  end

  def event_name_accounts_organizations_count do
    [:tuist, :accounts, :organizations, :count]
  end

  def event_name_storage_get_object_as_string_size do
    [:tuist, :storage, :get_object_size]
  end

  def event_name_storage_delete_all_objects do
    [:tuist, :storage, :delete_all_objects]
  end

  def event_name_storage_multipart_start_upload do
    [:tuist, :storage, :multipart, :start_upload]
  end

  def event_name_storage_get_object_as_string do
    [:tuist, :storage, :get_object_as_string]
  end

  def event_name_storage_check_object_existence do
    [:tuist, :storage, :check_object_existence]
  end

  def event_name_storage_generate_download_presigned_url do
    [:tuist, :storage, :generate_download_presigned_url]
  end

  def event_name_storage_generate_upload_presigned_url do
    [:tuist, :storage, :generate_upload_presigned_url]
  end

  def event_name_storage_multipart_complete_upload do
    [:tuist, :storage, :multipart, :complete_upload]
  end

  def event_name_storage_multipart_generate_upload_part_presigned_url do
    [:tuist, :storage, :multipart, :generate_upload_part_presigned_url]
  end

  def event_name_storage_stream_object do
    [:tuist, :storage, :stream_object]
  end

  def event_name_run_command do
    [:tuist, :run, :command]
  end

  def event_name_cache do
    [:tuist, :cache, :event]
  end

  def event_name_repo_pool_metrics do
    [:tuist, :repo, :pool, :metrics]
  end
end
