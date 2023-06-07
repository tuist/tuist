# frozen_string_literal: true

Then("the product {string} with destination {string} contains \
the framework {string} with architecture {string}") do |product, destination, framework, architecture|
  framework_path = Xcode.find_framework(
    product: product,
    destination: destination,
    framework: framework,
    derived_data_path: @derived_data_path
  )
  flunk("Framework #{framework} not found") if framework_path.nil?

  binary_path = File.join(framework_path, framework)
  out, err, status = Open3.capture3("file", binary_path)
  assert(status.success?, err)
  assert(out.include?(architecture))
end

Then("the product {string} with destination {string} contains \
the framework {string} without architecture {string}") do |product, destination, framework, architecture|
  framework_path = Xcode.find_framework(
    product: product,
    destination: destination,
    framework: framework,
    derived_data_path: @derived_data_path
  )
  flunk("Framework #{framework} not found") if framework_path.nil?

  binary_path = File.join(framework_path, framework)
  out, err, status = Open3.capture3("file", binary_path)
  assert(status.success?, err)
  refute(out.include?(architecture))
end

Then("the product {string} with destination {string} does \
not contain the framework {string}") do |product, destination, framework|
  framework_path = Xcode.find_framework(
    product: product,
    destination: destination,
    framework: framework,
    derived_data_path: @derived_data_path
  )
  flunk("Framework #{framework} found") unless framework_path.nil?
end

Then("the product {string} with destination {string} contains resource {string}") do |product, destination, resource|
  resource_path = Xcode.find_resource(
    product: product,
    destination: destination,
    resource: resource,
    derived_data_path: @derived_data_path
  )
  flunk("Product with name #{product} and destination #{destination} not found in DerivedData") if resource_path.nil?

  assert(resource_path)
end

Then("the product {string} with destination {string} does \
not contain resource {string}") do |product, destination, resource|
  resource_path = Xcode.find_resource(
    product: product,
    destination: destination,
    resource: resource,
    derived_data_path: @derived_data_path
  )
  flunk("Resource #{resource} found in product #{product} and destination #{destination}") unless resource_path.nil?

  refute(resource_path)
end

Then("the product {string} with destination {string} contains \
the Info.plist key {string}") do |product, destination, key|
  info_plist_path = Xcode.find_resource(
    product: product,
    destination: destination,
    resource: "Info.plist",
    derived_data_path: @derived_data_path
  )
  flunk("Product with name #{product} and destination #{destination} not found in DerivedData") if info_plist_path.nil?

  unless system("/usr/libexec/PlistBuddy -c \"print :#{key}\" #{info_plist_path}")
    flunk("Key #{key} not found in the #{product} Info.plist")
  end
end

Then("the product {string} with destination {string} contains \
the Info.plist key {string} with value {string}") do |product, destination, key, value|
  info_plist_path = Xcode.find_resource(
    product: product,
    destination: destination,
    resource: "Info.plist",
    derived_data_path: @derived_data_path
  )
  flunk("Product with name #{product} and destination #{destination} not found in DerivedData") if info_plist_path.nil?

  output = %x(/usr/libexec/PlistBuddy -c \"print :#{key}\" #{info_plist_path})

  flunk("Key #{key} not found in the #{product} Info.plist") if output.nil?

  assert(output == "#{value}\n")
end

Then("the product {string} with destination {string} contains extension {string}") do |product, destination, extension|
  extension_path = Xcode.find_extension(
    product: product,
    destination: destination,
    extension: extension,
    derived_data_path: @derived_data_path
  )
  flunk("Product with name #{product} and destination #{destination} not found in DerivedData") if extension_path.nil?

  assert(extension_path)
end

Then("the product {string} with destination {string} contains extensionKit extension {string}") do |product, destination, extension|
  extension_path = Xcode.find_extensionKitExtension(
    product: product,
    destination: destination,
    extension: extension,
    derived_data_path: @derived_data_path
  )
  flunk("Product with name #{product} and destination #{destination} not found in DerivedData") if extension_path.nil?

  assert(extension_path)
end

Then("the product {string} with destination {string} does not contain headers") do |product, destination|
  headers_paths = Xcode.find_headers(
    product: product,
    destination: destination,
    derived_data_path: @derived_data_path
  )
  flunk("Product with name #{product} and destination #{destination} contains headers") if headers_paths.any?

  assert_empty(headers_paths)
end

Then(/^a file (.+) exists$/) do |file|
  file_path = File.join(@dir, file)
  assert(File.file?(file_path), "#{file_path} does not exist")
end

Then(/^a file (.+) does not exist$/) do |file|
  file_path = File.join(@dir, file)
  assert(!File.file?(file_path), "#{file_path} does exist")
end

Then(/^a directory (.+) exists$/) do |directory|
  directory_path = File.join(@dir, directory)
  assert(Dir.exist?(directory_path), "#{directory_path} does not exist")
end

Then("the product {string} with destination {string} contains \
the appClip {string} with architecture {string}") do |product, destination, app_clip, architecture|
  app_clip_path = Xcode.find_app_clip(
    product: product,
    destination: destination,
    app_clip: app_clip,
    derived_data_path: @derived_data_path
  )
  flunk("AppClip #{app_clip} not found") if app_clip_path.nil?

  binary_path = File.join(app_clip_path, app_clip)
  out, err, status = Open3.capture3("file", binary_path)
  assert(status.success?, err)
  assert(out.include?(architecture))
end

Then("the product {string} with destination {string} contains \
the appClip {string} without architecture {string}") do |product, destination, app_clip, architecture|
  app_clip_path = Xcode.find_app_clip(
    product: product,
    destination: destination,
    app_clip: app_clip,
    derived_data_path: @derived_data_path
  )
  flunk("AppClip #{app_clip} not found") if app_clip_path.nil?

  binary_path = File.join(app_clip_path, app_clip)
  out, err, status = Open3.capture3("file", binary_path)
  assert(status.success?, err)
  refute(out.include?(architecture))
end
