# EConnect

A small GTK4/Granite app for elementary OS that talks the KDE Connect protocol, so the stock KDE Connect app on your Android or iOS phone works with it unchanged.

## Features

- Pair with phones on the same Wi-Fi network
- Clipboard sync in both directions
- Send and receive files, links and text
- Take a screenshot and send it to the phone
- Preview of the newest photos and screenshots from the phone

## Build and install

Dependencies (elementary OS 8 / Ubuntu):

```sh
sudo apt install meson valac libgtk-4-dev libgranite-7-dev libjson-glib-dev libgnutls28-dev
```

Build and install:

```sh
meson setup build
ninja -C build
sudo ninja -C build install
```

Run with `io.github.gornostal.econnect`, or from the applications menu. A headless test tool, `econnect-cli`, is built alongside it.
