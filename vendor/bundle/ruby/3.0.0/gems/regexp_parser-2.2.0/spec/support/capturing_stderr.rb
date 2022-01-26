require 'stringio'

def capturing_stderr(&block)
  old_stderr, $stderr = $stderr, StringIO.new
  block.call
  $stderr.string
ensure
  $stderr = old_stderr
end
