# frozen_string_literal: true

require "open3"

module System
  def system(*args)
    log(args.join(" "))
    if ARGV.include?("--verbose")
      status = Open3.popen2e(args.join(" ")) do |stdin, stdout_stderr, wait_thread|
        Thread.new do
          stdout_stderr.each { |l| puts l }
        end
        stdin.close
        wait_thread.value
      end
      assert(status.success?)
    else
      out, err, status = Open3.capture3(args.join(" "))
      puts args.join(" ")
      puts out
      puts status
      assert(status.success?, err)
    end
  end

  def xcodebuild(*args)
    system("xcodebuild", *args)
  end
end

World(System)
