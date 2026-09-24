# README banner

`data/banner.png` is the hero image at the top of the project README. It is
generated from `banner.html` in this directory. Don't edit the PNG by hand.

## Regenerate

```sh
data/banner/render.sh
```

This opens `banner.html` in headless Chrome and saves a screenshot to
`data/banner.png`.

Requirements:

- Google Chrome or Chromium. The script looks for `google-chrome`, `chromium`
  and similar names. Set `CHROME=/path/to/binary` to use a different one.
- The **Inter** and **Inter Display** fonts, installed system-wide
  (`fc-list | grep Inter`). The page uses local fonts only, with no web
  fonts, so the render works offline.

## How it's built

- **Canvas:** a 1280×640 CSS layout (GitHub's social-preview ratio, 2:1),
  rendered at `--force-device-scale-factor=2`, so the output is 2560×1280 and
  stays sharp on HiDPI screens.
- **Rounded corners:** `.hero` has `border-radius: 28px`, and Chrome is run
  with `--default-background-color=00000000`, so the corners come out
  transparent. They look right on both GitHub's light and dark themes.
- **Background:** three radial gradients (blue, violet, pink) over a diagonal
  linear gradient, plus a faint grid masked to the text area.
- **Orbit:** a large rotated ellipse with a glow. It echoes the ring in the
  app logo and is masked out on the left, so it doesn't cross the text.
- **Screenshots:** taken from `data/screenshots/`, the same files the
  AppStream metainfo uses. Those PNGs include a transparent drop-shadow margin
  around the window, so each one sits in a `.crop` box that trims the margin
  (see the percentages in `.crop img`). Each is tilted with a 3D
  `rotateY`/`rotateZ` transform.
- **Logo:** `data/icons/logo.png`.

## Common edits

| Change | Where in `banner.html` |
| --- | --- |
| Tagline / description | `.tag` and `.sub` elements |
| Feature chips | `.chips` list |
| Colours | `.hero` `background` gradients, `.tag span` text gradient |
| Screenshot placement | `.shot.back` / `.shot.front` (`width`, `top`, `right`, `transform`) |
| Corner radius | `.hero` `border-radius` |

If you retake the screenshots and the shadow margin changes, update
`aspect-ratio` on `.crop` and `width` / `left` / `top` on `.crop img`. These
values are the window size and offset within the PNG, as a percentage of the
window size.

For quick iteration, open `banner.html` directly in a browser at 100% zoom. It
renders exactly as it does in the screenshot.

## Output size

The PNG is lossless and about 1.3 MB. Reducing it to a 256-colour palette
(pngquant, PIL `quantize`) makes the gradients band visibly, so it is kept at
full colour.
