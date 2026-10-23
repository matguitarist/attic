# Third-party notices

## System logos

`Attic/Resources/SystemLogos.xcassets` holds console, handheld, arcade and
computer logos from **Console Logos Professionally Redrawn + Official
Versions** (v2.1) by **Dan Patrick**:
https://archive.org/details/console-logos-professionally-redrawn-plus-official-versions

They aren't covered by Attic's MIT license. In the author's words: "I made
these originally for LaunchBox but they can be used elsewhere. I will always
appreciate credit if you use them. Needless to say, I don't own the rights to
the logos and these are NEVER to be sold in any way."

The logos themselves are trademarks of their respective owners (Nintendo,
Sega, Sony, Microsoft, SNK, Capcom, NEC, Atari and others), shown only to
identify each system. Attic isn't affiliated with or endorsed by any of them.

`scripts/import-system-logos.py` rebuilds the catalog from the original
download.

## Known BIOS checksums

`AtticKit/Sources/AtticEmulation/Resources/KnownBIOS.tsv` lists the names,
sizes and MD5 checksums of known good BIOS dumps, adapted from
**libretro-database**'s `dat/System.dat` (v1.19.0) by the libretro team:
https://github.com/libretro/libretro-database

It's under the Creative Commons Attribution-ShareAlike 4.0 International
license (https://creativecommons.org/licenses/by-sa/4.0/), not Attic's MIT
license; Attic changed it only by leaving out zipped sets and other columns.
It holds checksums only: Attic never ships or downloads BIOS files.
`scripts/import-known-bios.py` rebuilds it from the original.

## Switch 2 controller start-up

`AtticKit/Sources/AtticModels/Switch2Pad.swift` holds the USB start-up
commands and input report layout for Nintendo's Switch 2 controllers, from
the community's reverse engineering as used by **InputConfig**
(https://github.com/ryleighnewman/InputConfig, MIT) and **procon2-mac**
(https://github.com/caqlayan/procon2-mac), whose license reads:

    MIT License

    Copyright (c) 2026 Arda Caglayan Ercan

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
