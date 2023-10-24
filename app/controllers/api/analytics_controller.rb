# frozen_string_literal: true

module API
  class AnalyticsController < APIController
    def analytics
      # FIX:
      # The implementation assummed that the authenticated entity is a user
      # when in reality it can be a project too. This causes requests coming
      # from CI environments where the token is used to fail.
      if current_user
        CommandEventCreateService.call(
          project_slug: params[:project_id],
          user: current_user,
          project: @project,
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
      render(json: { status: "success", data: {} })
    end
  end
end
