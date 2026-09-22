/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * kdeconnect.clipboard: text-only clipboard sync via Gdk.Clipboard.
 */
namespace EConnect.App {

    public class ClipboardPlugin : Plugins.Plugin {
        public override string[] incoming_types {
            owned get { return { Core.Packet.TYPE_CLIPBOARD, Core.Packet.TYPE_CLIPBOARD_CONNECT }; }
        }

        public override string[] outgoing_types {
            owned get { return { Core.Packet.TYPE_CLIPBOARD, Core.Packet.TYPE_CLIPBOARD_CONNECT }; }
        }

        public bool enabled { get; set; default = true; }

        private Gdk.Clipboard clipboard;
        private string? current_text = null;
        private int64 current_timestamp = 0;      // ms, when current_text was set
        private string? last_received = null;

        public signal void clipboard_received (Core.Device device, string text);

        public ClipboardPlugin (Gdk.Display display) {
            clipboard = display.get_clipboard ();
            clipboard.changed.connect (on_local_change);
        }

        private void on_local_change () {
            if (!enabled || !clipboard.get_formats ().contain_mime_type ("text/plain")
                && !clipboard.get_formats ().contain_gtype (typeof (string))) {
                return;
            }
            clipboard.read_text_async.begin (null, (obj, res) => {
                string? text;
                try {
                    text = clipboard.read_text_async.end (res);
                } catch (Error e) {
                    debug ("clipboard read: %s", e.message);
                    return;
                }
                if (text == null || text == "" || text == current_text) {
                    return;
                }
                current_text = text;
                current_timestamp = GLib.get_real_time () / 1000;
                if (text == last_received) {
                    return;   // this change is the one we just applied from a device
                }
                broadcast (text);
            });
        }

        private void broadcast (string text) {
            if (daemon == null) {
                return;
            }
            foreach (var device in daemon.get_devices ()) {
                if (device.is_paired && device.is_reachable
                    && device.info.supports_incoming (Core.Packet.TYPE_CLIPBOARD)) {
                    device.send_packet (new Core.Packet (Core.Packet.TYPE_CLIPBOARD)
                        .set_string ("content", text)
                        .set_int ("timestamp", current_timestamp));
                }
            }
        }

        public override void device_connected (Core.Device device) {
            if (!enabled || current_text == null
                || !device.info.supports_incoming (Core.Packet.TYPE_CLIPBOARD_CONNECT)) {
                return;
            }
            device.send_packet (new Core.Packet (Core.Packet.TYPE_CLIPBOARD_CONNECT)
                .set_string ("content", current_text)
                .set_int ("timestamp", current_timestamp));
        }

        public override void handle_packet (Core.Device device, Core.Packet packet) {
            if (!enabled) {
                return;
            }
            string? content = packet.get_string ("content");
            if (content == null) {
                return;
            }
            int64 ts = packet.get_int ("timestamp", 0);
            if (packet.packet_type == Core.Packet.TYPE_CLIPBOARD_CONNECT) {
                if (ts == 0 || ts <= current_timestamp) {
                    return;   // our clipboard is newer or the peer has nothing
                }
            }
            if (content == current_text) {
                return;
            }
            last_received = content;
            current_text = content;
            current_timestamp = ts > 0 ? ts : GLib.get_real_time () / 1000;
            clipboard.set_text (content);
            clipboard_received (device, content);
        }
    }
}
