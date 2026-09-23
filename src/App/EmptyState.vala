/*
 * SPDX-License-Identifier: MIT
 *
 * Shown while no device has been found: what to check, and a way to look again.
 */
namespace EConnect.App {

    public class EmptyState : Gtk.Box {
        public signal void search_again ();
        public signal void get_app ();

        private Gtk.Label name_hint;

        public EmptyState () {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 6,
                    halign: Gtk.Align.CENTER, valign: Gtk.Align.CENTER,
                    margin_top: 24, margin_bottom: 24, margin_start: 24, margin_end: 24,
                    width_request: 360);
        }

        construct {
            /* Two waves spread out from the tile, one after the other. */
            var icon = new Gtk.Image.from_icon_name ("network-wireless-symbolic") { pixel_size = 26, hexpand = true, vexpand = true };
            var tile = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER };
            tile.add_css_class ("radar-tile");
            tile.append (icon);
            tile.hexpand = tile.vexpand = false;
            var wave1 = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER };
            wave1.add_css_class ("radar-wave");
            var wave2 = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER };
            wave2.add_css_class ("radar-wave");
            wave2.add_css_class ("second");
            var radar_space = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { width_request = 132, height_request = 132 };
            var radar = new Gtk.Overlay () { child = radar_space, halign = Gtk.Align.CENTER, margin_bottom = 6 };
            radar.add_overlay (wave1);
            radar.add_overlay (wave2);
            radar.add_overlay (tile);
            append (radar);

            var title = new Gtk.Label (_("Looking for Devices")) { wrap = true, justify = Gtk.Justification.CENTER };
            title.add_css_class ("empty-title");
            append (title);
            var description = new Gtk.Label (_("Your phone shows up here as soon as it is on the same Wi-Fi network with KDE Connect open.")) {
                wrap = true,
                justify = Gtk.Justification.CENTER,
                max_width_chars = 46
            };
            description.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            append (description);

            var steps = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { margin_top = 16, margin_bottom = 16 };
            steps.append (step (1, _("Install KDE Connect on your phone"), _("It is free on Google Play, F-Droid and the App Store.")));
            steps.append (step (2, _("Join the same Wi-Fi network"), _("Guest networks often keep devices from seeing each other.")));
            name_hint = new Gtk.Label ("");
            steps.append (step (3, _("Open KDE Connect"), null, name_hint));
            append (steps);

            var again = new Gtk.Button.with_label (_("Search Again"));
            again.add_css_class (Granite.STYLE_CLASS_SUGGESTED_ACTION);
            again.clicked.connect (() => search_again ());
            var install = new Gtk.Button.with_label (_("Get KDE Connect"));
            install.clicked.connect (() => get_app ());
            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { halign = Gtk.Align.CENTER };
            buttons.append (again);
            buttons.append (install);
            append (buttons);

            var trouble = new Gtk.Label (_("Still nothing? A firewall on this computer must allow TCP and UDP ports 1714–1764.")) {
                wrap = true,
                xalign = 0,
                margin_top = 16
            };
            trouble.add_css_class ("trouble");
            trouble.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            append (trouble);
        }

        public void set_computer_name (string name) {
            name_hint.label = _("This computer shows up as “%s”.").printf (name);
        }

        private Gtk.Widget step (int number, string title, string? detail, Gtk.Label? detail_label = null) {
            var num = new Gtk.Label (number.to_string ()) { valign = Gtk.Align.START };
            num.add_css_class ("step-number");
            var title_label = new Gtk.Label (title) { xalign = 0, wrap = true };
            title_label.add_css_class ("step-title");
            var small = detail_label ?? new Gtk.Label (detail);
            small.xalign = 0;
            small.wrap = true;
            small.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            small.add_css_class (Granite.STYLE_CLASS_SMALL_LABEL);
            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { hexpand = true };
            text.append (title_label);
            text.append (small);
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            box.add_css_class ("step");
            box.append (num);
            box.append (text);
            return box;
        }
    }
}
