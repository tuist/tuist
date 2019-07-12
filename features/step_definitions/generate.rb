# frozen_string_literal: true

Then("the product {string} with destination {string} contains the framework {string} with architecture {string}") do |product, destination, framework, architecture|
  framework_path = Xcode.find_framework(
    product: product,
    destination: destination,
    framework: framework,
    derived_data_path: @derived_data_path
  )
  binary_path = File.join(framework_path, framework)
  out, err, status = Open3.capture3("file", binary_path)
  assert(status.success?, err)
  assert(out.include?(architecture))
end

Then("the product {string} with destination {string} contains the framework {string} without architecture {string}") do |product, destination, framework, architecture|
  framework_path = Xcode.find_framework(
    product: product,
    destination: destination,
    framework: framework,
    derived_data_path: @derived_data_path
  )
  binary_path = File.join(framework_path, framework)
  out, err, status = Open3.capture3("file", binary_path)
  assert(status.success?, err)
  refute(out.include?(architecture))
end

Then("the product {string} with destination {string} contains resource {string}") do |product, destination, resource|
  resource_path = Xcode.find_resource(
    product: product,
    destination: destination,
    resource: resource,
    derived_data_path: @derived_data_path
  )

  assert(resource_path)
end

Then("the product {string} with destination {string} does not contain resource {string}") do |product, destination, resource|
  resource_path = Xcode.find_resource(
    product: product,
    destination: destination,
    resource: resource,
    derived_data_path: @derived_data_path
  )
  refute(resource_path)
end

Then("the product {string} with destination {string} contains the Info.plist key {string}") do |product, destination, key|
  info_plist_path = Xcode.find_resource(
    product: product,
    destination: destination,
    resource: "Info.plist",
    derived_data_path: @derived_data_path
  )
  unless info_plist_path
    flunk("Info.plist not found in the product #{product}")
    return
  end

  unless system("/usr/libexec/PlistBuddy -c \"print :#{key}\" #{info_plist_path}")
    flunk("Key #{key} not found in the #{product} Info.plist")
  end
end
