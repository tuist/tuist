Then(/^tuist warms the cache$/) do
  system("swift", "run", "tuist", "cache", "warm", "--path", @dir)
end
