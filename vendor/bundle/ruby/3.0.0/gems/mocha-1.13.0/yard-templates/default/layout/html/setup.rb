def init
  super
  return unless ENV['GOOGLE_ANALYTICS_WEB_PROPERTY_ID']
  sections[:layout] << :google_analytics
end
