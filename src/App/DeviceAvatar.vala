/*
 * SPDX-License-Identifier: MIT
 *
 * A device icon on a rounded tile with a status dot in the corner. The tile
 * takes the accent color while the device is connected.
 */
namespace EConnect.App {

    public class DeviceAvatar : Gtk.Box {
        private const string[] STATES = { "connected", "available", "pairing", "offline" };

        public bool large { get; construct; }

        private Gtk.Box tile;
        private Gtk.Box dot;

        public DeviceAvatar (Core.DeviceType type, bool large) {
            Object (large: large, halign: Gtk.Align.CENTER, valign: Gtk.Align.CENTER);
            ((Gtk.Image) tile.get_first_child ()).icon_name = Util.device_icon (type);
        }

        construct {
            var image = new Gtk.Image () {
                pixel_size = large ? 28 : 18,
                hexpand = true,
                vexpand = true
            };
            tile = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            tile.append (image);
            tile.add_css_class ("device-tile");
            /* Set explicitly so the expanding icon does not stretch the tile. */
            tile.hexpand = tile.vexpand = false;
            dot = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                halign = Gtk.Align.END,
                valign = Gtk.Align.END,
                can_target = false
            };
            dot.add_css_class ("status-dot");
            if (large) {
                tile.add_css_class ("large");
                dot.add_css_class ("large");
            }
            var overlay = new Gtk.Overlay () { child = tile };
            overlay.add_overlay (dot);
            append (overlay);
        }

        /** One of Util.device_state()'s values. */
        public void set_state (string state) {
            foreach (unowned string s in STATES) {
                tile.remove_css_class (s);
                dot.remove_css_class (s);
            }
            tile.add_css_class (state);
            dot.add_css_class (state);
        }
    }
}
