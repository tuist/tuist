# frozen_string_literal: true
# typed: true

class UpdateCacheEventCountsJob < Que::Job
  def run
    Account.all.each do |account|
      projects = Project.where(
        account_id: account.id,
      )
      cache_upload_event_count = projects.reduce(0) do |total, project|
        total + CacheEvent
          .where(project_id: project.id, created_at: 30.days.ago...Time.now, event_type: :upload)
          .count
      end

      cache_download_event_count = projects.reduce(0) do |total, project|
        total + CacheEvent
          .where(project_id: project.id, created_at: 30.days.ago...Time.now, event_type: :download)
          .count
      end

      account.update(
        cache_upload_event_count: cache_upload_event_count,
        cache_download_event_count: cache_download_event_count,
      )
    end
  end
end
