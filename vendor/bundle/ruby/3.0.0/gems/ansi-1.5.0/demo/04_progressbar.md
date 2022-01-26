# ANSI::Progressbar

Pretty progress bars are easy to construct.

    require 'ansi/progressbar'

    pbar = ANSI::Progressbar.new("Test Bar", 100)

Running the bar simply requires calling the #inc method during
a loop and calling `#finish` when done.

    100.times do |i|
      sleep 0.01
      pbar.inc
    end
    pbar.finish

We will use this same rountine in all the examples below, so lets
make a quick macro for it. Notice we have to use `#reset` first
before reusing the same progress bar.

    def run(pbar)
      pbar.reset
      100.times do |i|
        sleep 0.01
        pbar.inc
      end
      pbar.finish
      puts
    end

The progress bar can be stylized in almost any way.
The `#format` setter provides control over the parts
that appear on the line. For example, by default the
format is:

    pbar.format("%-14s %3d%% %s %s", :title, :percentage, :bar, :stat)

So lets vary it up to demonstrate the case.

    pbar.format("%-14s %3d%% %s %s", :title, :percentage, :stat, :bar)
    run(pbar)

The progress bar has an extra build in format intended for use with
file downloads called `#transer_mode`.

    pbar.transfer_mode
    run(pbar)

Calling this methods is the same as calling:

    pbar.format("%-14s %3d%% %s %s",:title, :percentage, :bar, :stat_for_file_transfer)
    run(pbar)

The `#style` setter allows each part of the line be modified with ANSI codes. And the
`#bar_mark` writer can be used to change the character used to make the bar.

    pbar.standard_mode
    pbar.style(:title => [:red], :bar=>[:blue])
    pbar.bar_mark = "="
    run(pbar)

