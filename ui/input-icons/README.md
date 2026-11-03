# Input device icons

Vendored from [Custom Brand Icons](https://github.com/elax46/custom-brand-icons),
under the MIT license in LICENSE.txt. manifest.json records the pinned revision,
original SVG URLs and SHA-256 hashes. Brand names and marks identify devices;
no affiliation or endorsement is implied.

SVG originals are unchanged. PNGs are transparent, aspect-preserving 128px
renders trimmed to their actual alpha bounds. A modest optical correction uses
long edges of 104px (dense symbols), 112px (elongated symbols), or 120px (thin
wordmarks), centred in a 128px canvas. Proportions are always preserved. At runtime
all icon fields are 48px, both with and without text. PNGs avoid an SVG image
plugin on older TVs. Homebar tints each mask at its native 128px resolution, then uses smooth
filtering and mipmaps to preserve edges during downscaling and focus animations.
It does not first rasterise the artwork into a 32/48px texture. No network is used.

Regenerate with `QT_QPA_PLATFORM=offscreen python tools/prepare-input-icons.py`
in an environment with PySide6. The command checks original source hashes and
records rendering geometry in the manifest; no download is needed.

Four artwork entries with `group: tv` form the separate Live TV picker. Consoles,
streamers and audio devices are never offered there. The original text TV remains
a selectable default.

TV symbols come from [Material Design Icons](https://github.com/Templarian/MaterialDesign),
Pictogrammers and contributors, under Apache 2.0. Those four manifest entries
record their own repository, revision and license. See LICENSE-MaterialDesign.txt,
LICENSE-Apache-2.0.txt and NOTICE.txt.

The HDMI catalogue also includes 12 generic Material Design device symbols
(soundbar, AV receiver, amplifier, projector, console, decoder, monitor, disc
player, speaker, speakers, streamer and satellite receiver). These entries have
`group: device`, translated names and Apache 2.0 provenance in the manifest.
Four port symbols from the same revision (`group: port`: USB drive, AV,
Component, SCART) are the default icons of those sources.
The HDMI picker sorts translated names alphabetically; assignments keep stable
ids, so adding or sorting entries never changes a saved device choice.
