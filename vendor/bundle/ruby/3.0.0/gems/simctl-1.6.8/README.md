# simctl

[![Build Status](https://travis-ci.org/plu/simctl.svg?branch=master)](https://travis-ci.org/plu/simctl) [![Gem Version](https://badge.fury.io/rb/simctl.svg)](https://badge.fury.io/rb/simctl) [![Coverage Status](https://coveralls.io/repos/plu/simctl/badge.svg?branch=master&service=github)](https://coveralls.io/github/plu/simctl?branch=master)

Ruby interface to xcrun simctl. Manage your iOS Simulators directly from a ruby script.

## Usage

```ruby
require 'simctl'

# Select the iOS 12.1 runtime
runtime = SimCtl.runtime(name: 'iOS 12.1')

# Select the iPhone 6 device type
devicetype = SimCtl.devicetype(name: 'iPhone 6')

# Create a new device
device = SimCtl.create_device 'Unit Tests @ iPhone 6 - 12.1', devicetype, runtime

# Boot the device
device.boot

# Launch a new Simulator.app instance
device.launch

# Wait for the device to be booted
device.wait {|d| d.state == :booted}

# Kill the Simulator.app instance again
device.shutdown
device.kill

# Wait until it did shutdown
device.wait {|d| d.state == :shutdown}

# Delete the device
device.delete
```

## License (MIT)

Copyright (C) 2019 Johannes Plunien

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
