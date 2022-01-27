########################################################################
# uname_test.rb
#
# Generic test script for general futzing. Modify as you see fit. This
# should generally be run via the 'rake example' task.
########################################################################
require 'sys/uname'
require 'rbconfig'
include Sys

puts "VERSION: " + Uname::VERSION
puts 'Nodename: ' + Uname.nodename
puts 'Sysname: ' + Uname.sysname
puts 'Version: ' + Uname.version
puts 'Release: ' + Uname.release
puts 'Machine: ' + Uname.machine # May be "unknown" on Win32

if RbConfig::CONFIG['host_os'] =~ /sun|solaris/i
  print "\nSolaris specific tests\n"
  puts "==========================="
  puts 'Architecture: ' + Uname.architecture
  puts 'Platform: ' + Uname.platform
  puts 'Instruction Set List: ' + Uname.isa_list.split.join(", ")
  puts 'Hardware Provider: ' + Uname.hw_provider
  puts 'Serial Number: ' + Uname.hw_serial_number.to_s
  puts 'SRPC Domain: ' + Uname.srpc_domain # might be empty
  puts 'DHCP Cache: ' + Uname.dhcp_cache # might be empty
end

if RbConfig::CONFIG['host_os'] =~ /powerpc|darwin|bsd|mach/i
  print "\nBSD/OS X specific tests\n"
  puts "======================="
  puts 'Model: ' + Uname.model
end

if RbConfig::CONFIG['host_os'] =~ /hpux/i
  print "\nHP-UX specific tests\n"
  puts "========================"
  puts "ID: " + Uname.id
end

print "\nTest finished successfully\n"
