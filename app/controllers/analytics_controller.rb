# frozen_string_literal: true

class AnalyticsController < ApplicationController
  def analytics
    project_id = ProjectFetchService.new.fetch_by_name(
      name: params[:project_name],
      account_name: params[:account_name],
      subject: current_user,
    ).id
    @commands_average_duration = {
      generate: CommandAverageService.call(
        project_id: project_id,
        command_name: "generate",
        user: current_user,
        start_date: start_date,
      ),
      cache_warm: CommandAverageService.call(
        project_id: project_id,
        command_name: "cache warm",
        user: current_user,
        start_date: start_date,
      ),
      build: CommandAverageService.call(
        project_id: project_id,
        command_name: "build",
        user: current_user,
        start_date: start_date,
      ),
      test: CommandAverageService.call(
        project_id: project_id,
        command_name: "test",
        user: current_user,
        start_date: start_date,
      ),
    }

    @commands_average_cache_hit_rate = {
      generate: CacheHitRateAverageService.call(
        project_id: project_id,
        command_name: "generate",
        user: current_user,
        start_date: start_date,
      ),
      cache_warm: CacheHitRateAverageService.call(
        project_id: project_id,
        command_name: "cache warm",
        user: current_user,
        start_date: start_date,
      ),
    }

    @targets_cache_hit_rate = TargetCacheHitRateService.call(
      project_id: project_id,
      user: current_user,
    )
      .sort_by { |target| target.hits + target.misses }
      .take(10)
    render('analytics/index')
  end

  def analytics_targets
    project_id = ProjectFetchService.new.fetch_by_name(
      name: params[:project_name],
      account_name: params[:account_name],
      subject: current_user,
    ).id

    @targets_cache_hit_rate = TargetCacheHitRateService.call(
      project_id: project_id,
      user: current_user,
      start_date: start_date,
    )

    unless params[:column].nil?
      @targets_cache_hit_rate = @targets_cache_hit_rate
        .sort_by do |target|
          target.send(params[:column])
        end

      if params[:direction] == 'desc'
        @targets_cache_hit_rate = @targets_cache_hit_rate.reverse
      end
    end
    render('analytics/targets')
  end

  private

  def start_date
    if !params[:date_range].nil?
      case params[:date_range]
      when 'last_7_days'
        7.days.ago.to_date
      when 'last_30_days'
        30.days.ago.to_date
      when 'last_90_days'
        90.days.ago.to_date
      when 'last_year'
        1.year.ago.to_date
      else
        30.days.ago
      end
    else
      30.days.ago
    end
  end
end
