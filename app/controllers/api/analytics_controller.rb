# frozen_string_literal: true

module API
  class AnalyticsController < APIController
    authorize_current_subject_type analytics: [:user, :project]

    def analytics
      CommandEventCreateService.call(
        project_slug: params[:project_id],
        user: current_user,
        project: current_project,
        name: params[:name],
        subcommand: params[:subcommand],
        command_arguments: params[:command_arguments],
        duration: params[:duration],
        client_id: params[:client_id],
        tuist_version: params[:tuist_version],
        swift_version: params[:swift_version],
        macos_version: params[:macos_version],
        cacheable_targets: params[:params][:cacheable_targets],
        local_cache_target_hits: params[:params][:local_cache_target_hits],
        remote_cache_target_hits: params[:params][:remote_cache_target_hits],
        is_ci: params[:is_ci],
      )
    end
  end
end
