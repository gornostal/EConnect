/*
 * SPDX-License-Identifier: MIT
 */
namespace EConnect.App {

    public class DeviceRow : Gtk.ListBoxRow {
        public Core.Device device { get; construct; }

        /** Shown instead of the connection state while a transfer runs. */
        public string? busy_text { get; set; default = null; }

        private Gtk.Label status_label;
        private DeviceAvatar avatar;

        public DeviceRow (Core.Device device) {
            Object (device: device);
        }

        construct {
            avatar = new DeviceAvatar (device.device_type, false);

            var name_label = new Gtk.Label (device.name) {
                halign = Gtk.Align.START,
                ellipsize = Pango.EllipsizeMode.END
            };
            name_label.add_css_class ("step-title");
            status_label = new Gtk.Label ("") {
                halign = Gtk.Align.START,
                ellipsize = Pango.EllipsizeMode.END
            };
            status_label.add_css_class (Granite.STYLE_CLASS_SMALL_LABEL);

            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { valign = Gtk.Align.CENTER };
            text.append (name_label);
            text.append (status_label);

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            box.append (avatar);
            box.append (text);
            child = box;

            device.reachable_changed.connect (refresh);
            device.paired_changed.connect (refresh);
            device.pairing.notify["state"].connect (refresh);
            notify["busy-text"].connect (refresh);
            refresh ();
        }

        public void refresh () {
            string state = Util.device_state (device);
            avatar.set_state (state);
            switch (state) {
                case "pairing":
                    status_label.label = device.pair_state == Core.PairState.REQUESTED_BY_PEER
                        ? _("Wants to pair") : _("Pairing…");
                    break;
                case "offline":
                    status_label.label = _("Offline");
                    break;
                case "connected":
                    status_label.label = _("Connected");
                    break;
                default:
                    status_label.label = _("Not paired");
                    break;
            }
            if (busy_text != null) {
                status_label.label = busy_text;
                status_label.remove_css_class (Granite.STYLE_CLASS_DIM_LABEL);
                status_label.add_css_class ("busy");
            } else {
                status_label.remove_css_class ("busy");
                status_label.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            }
        }
    }
}
