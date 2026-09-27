#!/bin/sh
set -e
cd "$(dirname "$0")"
flatpak run org.flatpak.Builder --user --install --force-clean --install-deps-from=flathub build-flatpak io.github.gornostal.econnect.yml
