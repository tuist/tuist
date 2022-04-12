# frozen_string_literal: true

class AnalyticsController < APIController
  def analytics
    puts "Analytics!"
    puts request
  end
end
