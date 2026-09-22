/*
 * SPDX-License-Identifier: MIT
 */
namespace EConnect.App {

    public class PairDialog : Granite.Dialog {
        public Core.Device device { get; construct; }
        public bool incoming { get; construct; }

        private Gtk.Label code_label;

        public PairDialog (Gtk.Window parent, Core.Device device, bool incoming) {
            Object (device: device, incoming: incoming, transient_for: parent, modal: true);
        }

        construct {
            var icon = new Gtk.Image.from_icon_name (device.device_type.icon_name ()) {
                pixel_size = 64
            };

            var title = new Gtk.Label (incoming
                ? _("%s wants to pair").printf (device.name)
                : _("Pairing with %s").printf (device.name)) {
                wrap = true
            };
            title.add_css_class (Granite.STYLE_CLASS_H2_LABEL);

            var hint = new Gtk.Label (_("Make sure this code is shown on the other device too.")) {
                wrap = true
            };
            hint.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);

            code_label = new Gtk.Label (device.verification_key () ?? "········") {
                selectable = true,
                margin_top = 12,
                margin_bottom = 12
            };
            code_label.add_css_class (Granite.STYLE_CLASS_H1_LABEL);
            code_label.add_css_class (Granite.STYLE_CLASS_KEYCAP);

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
                margin_start = 24, margin_end = 24, margin_top = 12, margin_bottom = 12,
                halign = Gtk.Align.CENTER
            };
            box.append (icon);
            box.append (title);
            box.append (code_label);
            box.append (hint);
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
                destroy ();
            });

            device.paired_changed.connect (on_state_changed);
            device.reachable_changed.connect (on_state_changed);
            debug ("Pair dialog for %s (%s), code %s", device.name, incoming ? "incoming" : "outgoing",
                   device.verification_key () ?? "?");
        }

        private void on_state_changed () {
            if (device.pair_state == Core.PairState.PAIRED || device.pair_state == Core.PairState.NOT_PAIRED
                || !device.is_reachable) {
                device.paired_changed.disconnect (on_state_changed);
                device.reachable_changed.disconnect (on_state_changed);
                destroy ();
            }
        }
    }
}
