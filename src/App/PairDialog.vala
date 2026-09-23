/*
 * SPDX-License-Identifier: MIT
 */
namespace EConnect.App {

    public class PairDialog : Granite.Dialog {
        public Core.Device device { get; construct; }
        public bool incoming { get; construct; }

        private Gtk.ProgressBar countdown;
        private uint tick_id = 0;

        public PairDialog (Gtk.Window parent, Core.Device device, bool incoming) {
            Object (device: device, incoming: incoming, transient_for: parent, modal: true);
        }

        construct {
            /* This computer, a dashed line, the other device. */
            var devices = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { halign = Gtk.Align.CENTER, margin_bottom = 6 };
            devices.append (pair_tile ("computer-symbolic", false));
            var line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { valign = Gtk.Align.CENTER };
            line.add_css_class ("pair-line");
            devices.append (line);
            devices.append (pair_tile (Util.device_icon (device.device_type), true));

            var title = new Gtk.Label (incoming
                ? _("%s wants to pair").printf (device.name)
                : _("Pairing with %s").printf (device.name)) {
                wrap = true,
                justify = Gtk.Justification.CENTER
            };
            title.add_css_class (Granite.STYLE_CLASS_H2_LABEL);

            var hint = new Gtk.Label (incoming
                ? _("Accept only if %s shows the same code.").printf (device.name)
                : _("Check that %s shows the same code, then accept there.").printf (device.name)) {
                wrap = true,
                justify = Gtk.Justification.CENTER,
                max_width_chars = 40
            };
            hint.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);

            /* One key per character, in two groups of four so it is easier to compare. */
            string key = device.verification_key () ?? "--------";
            var code = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5) {
                halign = Gtk.Align.CENTER,
                margin_top = 10,
                margin_bottom = 4
            };
            for (int i = 0; i < key.length; i++) {
                if (i == 4) {
                    code.append (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { width_request = 10 });
                }
                var k = new Gtk.Label (key.substring (i, 1));
                k.add_css_class ("code-key");
                code.append (k);
            }

            countdown = new Gtk.ProgressBar () {
                fraction = 1.0,
                margin_start = 72,
                margin_end = 72,
                margin_top = 6,
                tooltip_text = _("The request expires after %u seconds").printf (Core.PairingHandler.TIMEOUT_SECONDS)
            };
            countdown.add_css_class ("thin");
            countdown.add_css_class ("countdown");

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                margin_start = 12, margin_end = 12, margin_bottom = 12
            };
            box.append (devices);
            box.append (title);
            box.append (code);
            box.append (hint);
            box.append (countdown);
            get_content_area ().append (box);

            if (incoming) {
                add_button (_("Reject"), Gtk.ResponseType.REJECT);
                var accept = add_button (_("Accept"), Gtk.ResponseType.ACCEPT);
                accept.add_css_class (Granite.STYLE_CLASS_SUGGESTED_ACTION);
            } else {
                add_button (_("Cancel"), Gtk.ResponseType.CANCEL);
            }

            response.connect ((id) => {
                switch (id) {
                    case Gtk.ResponseType.ACCEPT:
                        device.accept_pairing ();
                        break;
                    case Gtk.ResponseType.REJECT:
                    case Gtk.ResponseType.CANCEL:
                        if (device.pair_state != Core.PairState.PAIRED) {
                            device.reject_pairing ();
                        }
                        break;
                    default:
                        break;
                }
                close_dialog ();
            });

            int64 started = GLib.get_monotonic_time ();
            double total = Core.PairingHandler.TIMEOUT_SECONDS * 1000000.0;
            tick_id = Timeout.add (250, () => {
                countdown.fraction = (1.0 - (GLib.get_monotonic_time () - started) / total).clamp (0, 1);
                return Source.CONTINUE;
            });

            device.paired_changed.connect (on_state_changed);
            device.reachable_changed.connect (on_state_changed);
        }

        private Gtk.Widget pair_tile (string icon_name, bool far) {
            var tile = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            tile.add_css_class ("pair-tile");
            if (far) {
                tile.add_css_class ("far");
            }
            tile.append (new Gtk.Image.from_icon_name (icon_name) { pixel_size = 24, hexpand = true, vexpand = true });
            tile.hexpand = tile.vexpand = false;
            return tile;
        }

        private void on_state_changed () {
            if (device.pair_state == Core.PairState.PAIRED || device.pair_state == Core.PairState.NOT_PAIRED
                || !device.is_reachable) {
                close_dialog ();
            }
        }

        private void close_dialog () {
            if (tick_id != 0) {
                Source.remove (tick_id);
                tick_id = 0;
            }
            device.paired_changed.disconnect (on_state_changed);
            device.reachable_changed.disconnect (on_state_changed);
            destroy ();
        }
    }
}
