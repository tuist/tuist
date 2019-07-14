# frozen_string_literal: true

Then("the product {string} with destination {string} contains the framework {string} with architecture {string}") do |product, destination, framework, architecture|
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

Then("the product {string} with destination {string} contains the framework {string} without architecture {string}") do |product, destination, framework, architecture|
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

Then("the product {string} with destination {string} does not contain resource {string}") do |product, destination, resource|
  resource_path = Xcode.find_resource(
    product: product,
    destination: destination,
    resource: resource,
    derived_data_path: @derived_data_path
  )
  flunk("Resource #{resource} found in product #{product} and destination #{destination}") unless resource_path.nil?

  refute(resource_path)
end

Then("the product {string} with destination {string} contains the Info.plist key {string}") do |product, destination, key|
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
