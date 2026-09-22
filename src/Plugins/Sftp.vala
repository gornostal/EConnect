/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * kdeconnect.sftp: ask the phone to start its SFTP server and report the
 * credentials. Android only; the iOS app has no SFTP plugin.
 */
namespace EConnect.Plugins {

    public class SftpInfo : Object {
        public string host { get; set; }
        public uint16 port { get; set; }
        public string user { get; set; }
        public string password { get; set; }
        /** Browsable roots on the phone, e.g. /storage/emulated/0. */
        public string[] roots { get; set; default = {}; }
        public string[] root_names { get; set; default = {}; }

        public string uri () {
            return "sftp://%s@%s:%u/".printf (Uri.escape_string (user, null, false), host, port);
        }
    }

    public class Sftp : Plugin {
        public override string[] incoming_types {
            owned get { return { Core.Packet.TYPE_SFTP }; }
        }

        public override string[] outgoing_types {
            owned get { return { Core.Packet.TYPE_SFTP_REQUEST }; }
        }

        public signal void ready (Core.Device device, SftpInfo info);
        public signal void failed (Core.Device device, string reason);

        public static bool supported_by (Core.Device device) {
            return device.info.supports_outgoing (Core.Packet.TYPE_SFTP)
                && device.info.supports_incoming (Core.Packet.TYPE_SFTP_REQUEST);
        }

        /** Ask the phone to start its SFTP server. Reply arrives via `ready`. */
        public bool request_browsing (Core.Device device) {
            if (!supported_by (device)) {
                return false;
            }
            return device.send_packet (new Core.Packet (Core.Packet.TYPE_SFTP_REQUEST)
                .set_bool ("startBrowsing", true));
        }

        public override void handle_packet (Core.Device device, Core.Packet packet) {
            if (packet.has ("errorMessage")) {
                failed (device, packet.get_string ("errorMessage"));
                return;
            }
            var info = new SftpInfo ();
            info.host = packet.get_string ("ip", "");
            if (info.host == "" || info.host == "0.0.0.0") {
                info.host = device.link != null ? device.link.remote_address.get_address ().to_string () : "";
            }
            info.port = (uint16) packet.get_int ("port", 1739);
            info.user = packet.get_string ("user", "kdeconnect");
            info.password = packet.get_string ("password", "");
            info.roots = packet.get_string_array ("multiPaths");
            info.root_names = packet.get_string_array ("pathNames");
            if (info.roots.length == 0 && packet.has ("path")) {
                info.roots = { packet.get_string ("path") };
                info.root_names = { "Storage" };
            }
            if (info.host == "" || info.password == "") {
                failed (device, "Incomplete SFTP details from the phone");
                return;
            }
            ready (device, info);
        }
    }
}
