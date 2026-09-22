/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * kdeconnect.share.request: files (as payload), text and URLs, both ways.
 */
namespace EConnect.Plugins {

    public class Share : Plugin {
        public override string[] incoming_types {
            owned get { return { Core.Packet.TYPE_SHARE_REQUEST }; }
        }

        public override string[] outgoing_types {
            owned get { return { Core.Packet.TYPE_SHARE_REQUEST }; }
        }

        /** Where received files land. Defaults to the XDG download directory. */
        public File download_dir { get; set; }

        public signal void text_received (Core.Device device, string text);
        public signal void url_received (Core.Device device, string url);
        public signal void file_started (Core.Device device, string filename, int64 size);
        public signal void file_progress (Core.Device device, string filename, int64 done, int64 size);
        public signal void file_received (Core.Device device, File file);
        public signal void file_failed (Core.Device device, string filename, string reason);

        public Share () {
            string? dir = Environment.get_user_special_dir (UserDirectory.DOWNLOAD);
            download_dir = File.new_for_path (dir ?? Path.build_filename (Environment.get_home_dir (), "Downloads"));
        }

        public override void handle_packet (Core.Device device, Core.Packet packet) {
            if (packet.has_payload) {
                receive_file.begin (device, packet);
            } else if (packet.has ("text")) {
                text_received (device, packet.get_string ("text"));
            } else if (packet.has ("url")) {
                url_received (device, packet.get_string ("url"));
            } else {
                debug ("Share packet from %s without text, url or payload", device.name);
            }
        }

        /* ---- receiving -------------------------------------------------- */

        private File unique_target (string filename) {
            string safe = Path.get_basename (filename).replace ("/", "_");
            if (safe == "" || safe == "." || safe == "..") {
                safe = "received-file";
            }
            var target = download_dir.get_child (safe);
            if (!target.query_exists ()) {
                return target;
            }
            int dot = safe.last_index_of_char ('.');
            string stem = dot > 0 ? safe.substring (0, dot) : safe;
            string ext = dot > 0 ? safe.substring (dot) : "";
            for (int i = 1; ; i++) {
                target = download_dir.get_child ("%s (%d)%s".printf (stem, i, ext));
                if (!target.query_exists ()) {
                    return target;
                }
            }
        }

        private async void receive_file (Core.Device device, Core.Packet packet) {
            string filename = packet.get_string ("filename", "received-file");
            int64 size = packet.payload_size;
            var link = device.link;
            if (link == null) {
                file_failed (device, filename, "Device went offline");
                return;
            }
            file_started (device, filename, size);
            File target = unique_target (filename);
            try {
                if (!download_dir.query_exists ()) {
                    download_dir.make_directory_with_parents ();
                }
                var stream = yield link.open_payload (packet);
                var output = yield target.replace_async (null, false, FileCreateFlags.REPLACE_DESTINATION);
                uint8 buffer[65536];
                int64 done = 0;
                while (size < 0 || done < size) {
                    ssize_t n = yield stream.input_stream.read_async (buffer);
                    if (n <= 0) {
                        break;
                    }
                    size_t written;
                    yield output.write_all_async (buffer[0:n], Priority.DEFAULT, null, out written);
                    done += n;
                    file_progress (device, filename, done, size);
                }
                yield output.close_async ();
                try {
                    yield stream.close_async ();
                } catch (Error e) {
                    debug ("closing payload stream: %s", e.message);
                }
                if (size >= 0 && done != size) {
                    throw new IOError.PARTIAL_INPUT ("Received %s of %s bytes",
                                                     done.to_string (), size.to_string ());
                }
                int64 modified_ms = packet.get_int ("lastModified", 0);
                if (modified_ms > 0) {
                    try {
                        var fi = new FileInfo ();
                        fi.set_attribute_uint64 (FileAttribute.TIME_MODIFIED, (uint64) (modified_ms / 1000));
                        yield target.set_attributes_async (fi, FileQueryInfoFlags.NONE, Priority.DEFAULT, null, null);
                    } catch (Error e) {
                        debug ("mtime: %s", e.message);
                    }
                }
                GLib.info ("Received %s from %s", target.get_path (), device.name);
                file_received (device, target);
            } catch (Error e) {
                warning ("Receiving %s from %s failed: %s", filename, device.name, e.message);
                try {
                    if (target.query_exists ()) {
                        target.delete ();
                    }
                } catch (Error e2) {
                    /* ignore */
                }
                file_failed (device, filename, e.message);
            }
        }

        /* ---- sending ---------------------------------------------------- */

        public bool send_text (Core.Device device, string text) {
            return device.send_packet (new Core.Packet (Core.Packet.TYPE_SHARE_REQUEST).set_string ("text", text));
        }

        public bool send_url (Core.Device device, string url) {
            return device.send_packet (new Core.Packet (Core.Packet.TYPE_SHARE_REQUEST).set_string ("url", url));
        }

        public async void send_file (Core.Device device, File file, Cancellable? cancel = null) throws Error {
            var link = device.link;
            if (link == null) {
                throw new IOError.NOT_CONNECTED ("%s is not reachable", device.name);
            }
            var fi = yield file.query_info_async ("standard::size,standard::display-name,time::modified,time::created",
                                                  FileQueryInfoFlags.NONE, Priority.DEFAULT, cancel);
            int64 size = fi.get_size ();
            var packet = new Core.Packet (Core.Packet.TYPE_SHARE_REQUEST)
                .set_string ("filename", fi.get_display_name ())
                .set_int ("numberOfFiles", 1)
                .set_int ("totalPayloadSize", size);
            var modified = fi.get_modification_date_time ();
            if (modified != null) {
                packet.set_int ("lastModified", modified.to_unix () * 1000);
            }
            if (fi.has_attribute (FileAttribute.TIME_CREATED)) {
                packet.set_int ("creationTime", (int64) fi.get_attribute_uint64 (FileAttribute.TIME_CREATED) * 1000);
            }
            var input = yield file.read_async (Priority.DEFAULT, cancel);
            yield link.send_payload_packet (packet, input, size, cancel);
            GLib.info ("Sent %s to %s", file.get_path (), device.name);
        }
    }
}
