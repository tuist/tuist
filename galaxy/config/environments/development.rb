# frozen_string_literal: true

Rails.application.configure do
  config.eager_load = false
  config.consider_all_requests_local = true

  # Cache
  config.cache_classes = false
  if Rails.root.join('tmp', 'caching-dev.txt').exist?
    config.action_controller.perform_caching = true

    config.cache_store = :memory_store
    config.public_file_server.headers = {
      'Cache-Control' => "public, max-age=#{2.days.to_i}",
    }
  else
    config.action_controller.perform_caching = false
    config.cache_store = :null_store
  end

  # Active support
  config.active_support.deprecation = :log

  # Active record
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true

  # Assets
  config.assets.debug = true
  config.assets.quiet = true
  config.file_watcher = ActiveSupport::EventedFileUpdateChecker
end
