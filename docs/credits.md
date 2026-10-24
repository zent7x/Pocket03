# Credits and third-party material

## Typography

VT323 © 2011 The VT323 Project Authors (Peter Hull), under the SIL Open Font License 1.1. The
font and its full licence text ship in `Pocket03/Fonts/`.

## Handset images

`Pocket03/Assets.xcassets/nokia2630.imageset` is derived from a freely licensed photograph:

- **File:** *Nokia 2630 w polskiej sieci Play pod koniec 2018 roku.jpg*
- **Source:** https://commons.wikimedia.org/wiki/File:Nokia_2630_w_polskiej_sieci_Play_pod_koniec_2018_roku.jpg
- **Author:** Wikimedia Commons user `WrS.tm.pl`
- **Licence:** CC0 1.0 Universal (public domain dedication) — attribution is not legally
  required, and is given here anyway.
- **Changes:** EXIF rotation applied, cropped to the handset, lanyard and background removed,
  resized to 301 × 700.

The Dreamy (original) and Siemens CX70 entries currently use original handset illustrations drawn
at runtime in `Pocket03/PhoneGlyph.swift`. No freely licensed photograph of the Siemens CX70
exists on Wikimedia Commons — its only file there is a vendor promotional image whose free-licence
tag the uploader was not in a position to grant — and Dreamy is not a real handset, so no
photograph of it can exist. `PhoneGlyph` prefers a photograph wherever one is available and falls
back to the drawing otherwise, so adding further images is a matter of dropping in an imageset and
registering it in `PhoneGlyph.photographed`.

## Trademarks

"Nokia" and "Siemens" are trademarks of their respective owners. Pocket03 is not affiliated with,
sponsored by or endorsed by them. The model names are used only to describe which era of handset
camera a given look is reaching for, and no manufacturer logo or artwork is reproduced in the
drawn illustrations.

## Reverse-engineering boundary

Pocket03 bundles no asset, model, library or shader from the app that inspired it. See
[reconstruction.md](reconstruction.md).
