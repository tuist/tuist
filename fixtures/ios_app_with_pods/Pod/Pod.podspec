# frozen_string_literal: true

Pod::Spec.new do |s|
  s.name             = "Pod"
  s.version          = "0.1.0"
  s.summary          = "Test pod"
  s.description      = "This is just a test pod"
  s.homepage         = "https://github.com/tuist/tuist"
  s.license          = "MIT"
  s.author           = { "tuist" => "tuist@tuist.io" }
  s.source           = { git: "https://github.com/tuist/tuist.git", tag: s.version.to_s }
  s.ios.deployment_target = "8.0"
  s.source_files          = "Sources/**/*.{swift}"
  s.swift_version = "5.0"
end
