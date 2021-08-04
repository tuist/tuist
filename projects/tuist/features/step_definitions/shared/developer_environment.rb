# frozen_string_literal: true

require "fileutils"

Then(/I install the Workflow extensions SDK/) do
  sdk_pkg_path = File.expand_path("../../resources/WorkflowExtensionsSDK.pkg", __dir__)
  unless File.exist?("/Library/Developer/SDKs/WorkflowExtensionSDK.sdk")
    system("sudo", "installer", "-package", sdk_pkg_path, "-target", "/")
  end
end
