/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
namespace EConnect.Core {

    public enum DeviceType {
        DESKTOP, LAPTOP, PHONE, TABLET, TV;

        public string to_string () {
            switch (this) {
                case DESKTOP: return "desktop";
                case LAPTOP: return "laptop";
                case PHONE: return "phone";
                case TABLET: return "tablet";
                case TV: return "tv";
                default: return "desktop";
            }
        }

        public static DeviceType parse (string? s) {
            switch (s) {
                case "laptop": return LAPTOP;
                case "phone":
                case "smartphone": return PHONE;
                case "tablet": return TABLET;
                case "tv": return TV;
                default: return DESKTOP;
            }
        }

        public string icon_name () {
            switch (this) {
                case PHONE: return "phone";
                case TABLET: return "computer-apple-ipad";
                case TV: return "video-display";
                case LAPTOP: return "computer-laptop";
                default: return "computer";
            }
        }
    }

    public class DeviceInfo : Object {
        public string id { get; set; }
        public string name { get; set; }
        public DeviceType device_type { get; set; default = DeviceType.PHONE; }
        public int protocol_version { get; set; default = 0; }
        public string[] incoming_capabilities { get; set; default = {}; }
        public string[] outgoing_capabilities { get; set; default = {}; }
        public TlsCertificate? certificate { get; set; default = null; }

        public DeviceInfo (string id, string name, DeviceType type) {
            this.id = id;
            this.name = name;
            this.device_type = type;
        }

        public static bool is_valid_device_id (string? id) {
            return id != null && GLib.Regex.match_simple ("^[a-zA-Z0-9_-]{32,38}$", id);
        }

        public static string filter_name (string? input) {
            if (input == null) {
                return "";
            }
            string s;
            try {
                var re = new GLib.Regex ("[\"',;:.!?()\\[\\]<>]");
                s = re.replace_literal (input, -1, 0, "");
            } catch (GLib.RegexError e) {
                s = input;
            }
            if (s.char_count () > 32) {
                s = s.substring (0, s.index_of_nth_char (32));
            }
            return s;
        }

        public bool supports_incoming (string packet_type) {
            return packet_type in incoming_capabilities;
        }

        public bool supports_outgoing (string packet_type) {
            return packet_type in outgoing_capabilities;
        }

        /* ---- packets ---------------------------------------------------- */

        /** Plaintext, broadcast over UDP 1716. */
        public Packet to_udp_discovery_packet (uint16 tcp_port) {
            return new Packet (Packet.TYPE_IDENTITY)
                .set_string ("deviceId", id)
                .set_string ("deviceName", name)
                .set_int ("protocolVersion", protocol_version)
                .set_int ("tcpPort", tcp_port);
        }

        /** Plaintext, first line sent by the side that opens the TCP connection. */
        public Packet to_connection_packet (string target_device_id, int target_protocol_version) {
            return new Packet (Packet.TYPE_IDENTITY)
                .set_string ("deviceId", id)
                .set_string ("deviceName", name)
                .set_int ("protocolVersion", protocol_version)
                .set_string ("targetDeviceId", target_device_id)
                .set_int ("targetProtocolVersion", target_protocol_version);
        }

        /** Full identity, exchanged by both sides after the TLS handshake. */
        public Packet to_identity_packet () {
            return new Packet (Packet.TYPE_IDENTITY)
                .set_string ("deviceId", id)
                .set_string ("deviceName", name)
                .set_string ("deviceType", device_type.to_string ())
                .set_int ("protocolVersion", protocol_version)
                .set_string_array ("incomingCapabilities", incoming_capabilities)
                .set_string_array ("outgoingCapabilities", outgoing_capabilities);
        }

        public static bool is_valid_udp_discovery_packet (Packet p) {
            return p.packet_type == Packet.TYPE_IDENTITY
                && is_valid_device_id (p.get_string ("deviceId"));
        }

        public static bool is_valid_connection_packet (Packet p) {
            return p.packet_type == Packet.TYPE_IDENTITY
                && is_valid_device_id (p.get_string ("deviceId"))
                && is_valid_device_id (p.get_string ("targetDeviceId"));
        }

        public static bool is_valid_identity_packet (Packet p) {
            return p.packet_type == Packet.TYPE_IDENTITY
                && is_valid_device_id (p.get_string ("deviceId"))
                && filter_name (p.get_string ("deviceName")) != "";
        }

        public static DeviceInfo from_identity_packet (Packet p, TlsCertificate? cert) {
            var info = new DeviceInfo (p.get_string ("deviceId"),
                                       filter_name (p.get_string ("deviceName")),
                                       DeviceType.parse (p.get_string ("deviceType")));
            info.protocol_version = (int) p.get_int ("protocolVersion", -1);
            info.incoming_capabilities = p.get_string_array ("incomingCapabilities");
            info.outgoing_capabilities = p.get_string_array ("outgoingCapabilities");
            info.certificate = cert;
            return info;
        }
    }
}
