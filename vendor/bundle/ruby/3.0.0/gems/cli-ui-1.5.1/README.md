CLI UI
---

CLI UI is a small framework for generating nice command-line user interfaces

- [Master Documentation](http://www.rubydoc.info/github/Shopify/cli-ui/master/CLI/UI)
- [Documentation of the Rubygems version](http://www.rubydoc.info/gems/cli-ui/)
- [Rubygems](https://rubygems.org/gems/cli-ui)

## Installation

```bash
gem install cli-ui
```

or add the following to your Gemfile:

```ruby
gem 'cli-ui'
```

In your code, simply add a `require 'cli/ui'`. Most options assume `CLI::UI::StdoutRouter.enable` has been called.

## Features

This may not be an exhaustive list. Please check our [documentation](http://www.rubydoc.info/github/Shopify/cli-ui/master/CLI/UI) for more information.

---

### Nested framing
To handle content flow (see example below)

```ruby
CLI::UI::StdoutRouter.enable
CLI::UI::Frame.open('Frame 1') do
  CLI::UI::Frame.open('Frame 2') { puts "inside frame 2" }
  puts "inside frame 1"
end
```

![Nested Framing](https://user-images.githubusercontent.com/3074765/33799861-cb5dcb5c-dd01-11e7-977e-6fad38cee08c.png)

---

### Interactive Prompts
Prompt user with options and ask them to choose. Can answer using arrow keys, vim bindings (`j`/`k`), or numbers  (or y/n for yes/no questions).

For large numbers of options, using `e`, `:`, or `G` will toggle "line select" mode which allows numbers greater than 9 to be typed and
`f` or `/` will allow the user to filter options using a free-form text input.

```ruby
CLI::UI.ask('What language/framework do you use?', options: %w(rails go ruby python))
```

Can also assign callbacks to each option

```ruby
CLI::UI::Prompt.ask('What language/framework do you use?') do |handler|
  handler.option('rails')  { |selection| selection }
  handler.option('go')     { |selection| selection }
  handler.option('ruby')   { |selection| selection }
  handler.option('python') { |selection| selection }
end
```

* Note that the two examples provided above are identical in functionality

![Interactive Prompt](https://user-images.githubusercontent.com/3074765/33797984-0ebb5e64-dcdf-11e7-9e7e-7204f279cece.gif)

---

### Free form text prompts

```ruby
CLI::UI.ask('Is CLI UI Awesome?', default: 'It is great!')
```

  ![Free form text prompt](https://user-images.githubusercontent.com/3074765/33799822-47f23302-dd01-11e7-82f3-9072a5a5f611.png)

---

### Spinner groups
Handle many multi-threaded processes while suppressing output unless there is an issue. Can update title to show state.

```ruby
spin_group = CLI::UI::SpinGroup.new
spin_group.add('Title')   { |spinner| sleep 3.0 }
spin_group.add('Title 2') { |spinner| sleep 3.0; spinner.update_title('New Title'); sleep 3.0 }
spin_group.wait
```

![Spinner Group](https://user-images.githubusercontent.com/3074765/33798295-d94fd822-dce3-11e7-819b-43e5502d490e.gif)

---

### Text Color formatting
e.g. `{{red:Red}} {{green:Green}}`

```ruby
puts CLI::UI.fmt "{{red:Red}} {{green:Green}}"
```

![Text Format](https://user-images.githubusercontent.com/3074765/33799827-6d0721a2-dd01-11e7-9ab5-c3d455264afe.png)

---

### Symbol/Glyph Formatting
e.g. `{{*}}` => a yellow ⭑

```ruby
puts CLI::UI.fmt "{{*}} {{v}} {{?}} {{x}}"
```

![Symbol Formatting](https://user-images.githubusercontent.com/3074765/33799847-9ec03fd0-dd01-11e7-93f7-5f5cc540e61e.png)

---

### Status Widget

```ruby
CLI::UI::Spinner.spin("building packages: {{@widget/status:1:2:3:4}}") do |spinner|
  # spinner.update_title(...)
  sleep(3)
end
```

![Status Widget](https://user-images.githubusercontent.com/1284/61405142-11042580-a8a7-11e9-9885-46ba44c46358.gif)

---

### Progress Bar

Show progress of a process or operation.

```ruby
CLI::UI::Progress.progress do |bar|
  100.times do
    bar.tick
  end
end
```

![Progress Bar](https://user-images.githubusercontent.com/3074765/33799794-cc4c940e-dd00-11e7-9bdc-90f77ec9167c.gif)

---

### Frame Styles

Modify the appearance of CLI::UI both globally and on an individual frame level.

To set the default style:

```ruby
CLI::UI.frame_style = :box
```

To style an individual frame:

```ruby
CLI::UI.frame('New Style!', frame_style: :bracket) { puts 'It's pretty cool!' }
```

The default style - `:box` - is what has been used up until now.  The other style - `:bracket` - looks like this:

```ruby
CLI::UI.frame_style = :bracket
CLI::UI::StdoutRouter.enable
CLI::UI::Frame.open('Frame 1') do
  CLI::UI::Frame.open('Frame 2') { puts "inside frame 2" }
  puts "inside frame 1"
end
```

![Frame Style](https://user-images.githubusercontent.com/315948/65287373-9a82de80-db08-11e9-94fb-20f4b7561c07.png)

---

## Example Usage

The following code makes use of nested-framing, multi-threaded spinners, formatted text, and more.

```ruby
require 'cli/ui'

CLI::UI::StdoutRouter.enable

CLI::UI::Frame.open('{{*}} {{bold:a}}', color: :green) do
  CLI::UI::Frame.open('{{i}} b', color: :magenta) do
    CLI::UI::Frame.open('{{?}} c', color: :cyan) do
      sg = CLI::UI::SpinGroup.new
      sg.add('wow') do |spinner|
        sleep(2.5)
        spinner.update_title('second round!')
        sleep (1.0)
      end
      sg.add('such spin') { sleep(1.6) }
      sg.add('many glyph') { sleep(2.0) }
      sg.wait
    end
  end
  CLI::UI::Frame.divider('{{v}} lol')
  puts CLI::UI.fmt '{{info:words}} {{red:oh no!}} {{green:success!}}'
  sg = CLI::UI::SpinGroup.new
  sg.add('more spins') { sleep(0.5) ; raise 'oh no' }
  sg.wait
end
```

Output:

![Example Output](https://user-images.githubusercontent.com/3074765/33797758-7a54c7cc-dcdb-11e7-918e-a47c9689f068.gif)

## Development

- Run tests using `bundle exec rake test`. All code should be tested.
- No code, outside of development and tests needs, should use dependencies. This is a self contained library

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Shopify/cli-ui.

## License

The code is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
