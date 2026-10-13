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
