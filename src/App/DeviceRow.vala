/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
namespace EConnect.App {

    public class DeviceRow : Gtk.ListBoxRow {
        public Core.Device device { get; construct; }

        private Gtk.Label status_label;
        private Gtk.Image icon;

        public DeviceRow (Core.Device device) {
            Object (device: device);
        }

        construct {
            icon = new Gtk.Image.from_icon_name (device.device_type.icon_name ()) {
                pixel_size = 32
            };
            var name_label = new Gtk.Label (device.name) {
                halign = Gtk.Align.START,
                ellipsize = Pango.EllipsizeMode.END
            };
            name_label.add_css_class (Granite.STYLE_CLASS_H3_LABEL);
            status_label = new Gtk.Label ("") {
                halign = Gtk.Align.START,
                ellipsize = Pango.EllipsizeMode.END
            };
            status_label.add_css_class (Granite.STYLE_CLASS_SMALL_LABEL);
            status_label.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);

            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { valign = Gtk.Align.CENTER };
            text.append (name_label);
            text.append (status_label);

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
                margin_top = 6, margin_bottom = 6, margin_start = 12, margin_end = 12
            };
            box.append (icon);
            box.append (text);
            child = box;

            device.reachable_changed.connect (refresh);
            device.paired_changed.connect (refresh);
            refresh ();
        }

        public void refresh () {
            string state;
            if (!device.is_reachable) {
                state = _("Offline");
            } else if (device.pair_state == Core.PairState.PAIRED) {
                state = _("Connected");
            } else if (device.pair_state == Core.PairState.REQUESTED
                       || device.pair_state == Core.PairState.REQUESTED_BY_PEER) {
                state = _("Pairing…");
            } else {
                state = _("Available, not paired");
            }
            status_label.label = state;
            icon.opacity = device.is_reachable ? 1.0 : 0.4;
        }
    }
}
