# ANSI::BBCode

The BBCode module provides methods for converting between
BBCodes, basic HTML and ANSI codes.

    require 'ansi/bbcode'

BBCodes are color and style codes in square brackets, quite
popular with on line forums.

    bbcode = "this is [COLOR=red]red[/COLOR], this is [B]bold[/B]"

We can convert this to ANSI code simply enough:

    ansi = ANSI::BBCode.bbcode_to_ansi(bbcode)

    ansi.assert == "this is \e[0;31mred\e[0m, this is \e[1mbold\e[0m\n"

In addition the BBCode module supports conversion to simple HTML.

    html = ANSI::BBCode.bbcode_to_html(bbcode)

    html.assert == "this is <font color=\"red\">red</font>, this is <strong>bold</strong><br />\n"

