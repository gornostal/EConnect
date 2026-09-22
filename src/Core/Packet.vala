/*
 * SPDX-License-Identifier: MIT
 *
 * A KDE Connect network packet: one line of JSON, newline terminated.
 *
 *   {"id": <epoch ms>, "type": "kdeconnect.xxx", "body": {...},
 *    "payloadSize": <bytes>, "payloadTransferInfo": {"port": N}}
 */
namespace EConnect.Core {

    public errordomain PacketError {
        INVALID
    }

    public class Packet : Object {
        public const int PROTOCOL_VERSION = 8;
        public const int MAX_IDENTITY_PACKET_SIZE = 8192;

        public const string TYPE_IDENTITY = "kdeconnect.identity";
        public const string TYPE_PAIR = "kdeconnect.pair";
        public const string TYPE_PING = "kdeconnect.ping";
        public const string TYPE_CLIPBOARD = "kdeconnect.clipboard";
        public const string TYPE_CLIPBOARD_CONNECT = "kdeconnect.clipboard.connect";
        public const string TYPE_SHARE_REQUEST = "kdeconnect.share.request";
        public const string TYPE_SHARE_REQUEST_UPDATE = "kdeconnect.share.request.update";
        public const string TYPE_SFTP = "kdeconnect.sftp";
        public const string TYPE_SFTP_REQUEST = "kdeconnect.sftp.request";

        public string packet_type { get; private set; }
        public Json.Object body { get; private set; }

        /** 0 means no payload; -1 means a stream of unknown length. */
        public int64 payload_size { get; set; default = 0; }
        public Json.Object? payload_transfer_info { get; set; default = null; }

        /** For received packets: host the payload can be fetched from. */
        public InetAddress? payload_host { get; set; default = null; }

        public bool has_payload {
            get { return payload_size != 0; }
        }

        public Packet (string type) {
            packet_type = type;
            body = new Json.Object ();
        }

        public Packet.with_body (string type, Json.Object body) {
            packet_type = type;
            this.body = body;
        }

        public string serialize () {
            var root = new Json.Object ();
            root.set_int_member ("id", GLib.get_real_time () / 1000);
            root.set_string_member ("type", packet_type);
            root.set_object_member ("body", body);
            if (has_payload) {
                root.set_int_member ("payloadSize", payload_size);
                root.set_object_member ("payloadTransferInfo",
                                        payload_transfer_info ?? new Json.Object ());
            }

            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (root);
            var generator = new Json.Generator ();
            generator.set_root (node);
            return generator.to_data (null) + "\n";
        }

        public static Packet parse (string line) throws Error {
            var parser = new Json.Parser ();
            parser.load_from_data (line, -1);
            unowned Json.Node? root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                throw new PacketError.INVALID ("Packet is not a JSON object");
            }
            unowned Json.Object obj = root.get_object ();

            if (!is_string_node (obj.get_member ("type"))) {
                throw new PacketError.INVALID ("Packet has no string 'type'");
            }
            string type = obj.get_string_member ("type");
            if (!GLib.Regex.match_simple ("^kdeconnect(\\.[a-z_]+)+$", type)) {
                throw new PacketError.INVALID ("Bad packet type '%s'", type);
            }

            Json.Object body;
            unowned Json.Node? body_node = obj.get_member ("body");
            if (body_node != null && body_node.get_node_type () == Json.NodeType.OBJECT) {
                body = body_node.get_object ();
            } else {
                body = new Json.Object ();
            }

            var packet = new Packet.with_body (type, body);

            unowned Json.Node? size_node = obj.get_member ("payloadSize");
            if (is_number_node (size_node)) {
                packet.payload_size = size_node.get_int ();
            }
            unowned Json.Node? info_node = obj.get_member ("payloadTransferInfo");
            if (info_node != null && info_node.get_node_type () == Json.NodeType.OBJECT) {
                packet.payload_transfer_info = info_node.get_object ();
            }
            return packet;
        }

        /* ---- body accessors -------------------------------------------- */

        public bool has (string key) {
            return body.has_member (key);
        }

        public string? get_string (string key, string? fallback = null) {
            unowned Json.Node? node = body.get_member (key);
            return is_string_node (node) ? node.get_string () : fallback;
        }

        public int64 get_int (string key, int64 fallback = 0) {
            unowned Json.Node? node = body.get_member (key);
            return is_number_node (node) ? node.get_int () : fallback;
        }

        public bool get_bool (string key, bool fallback = false) {
            unowned Json.Node? node = body.get_member (key);
            if (node != null && node.get_node_type () == Json.NodeType.VALUE
                && node.get_value_type () == typeof (bool)) {
                return node.get_boolean ();
            }
            return fallback;
        }

        public string[] get_string_array (string key) {
            string[] result = {};
            unowned Json.Node? node = body.get_member (key);
            if (node == null || node.get_node_type () != Json.NodeType.ARRAY) {
                return result;
            }
            node.get_array ().foreach_element ((array, index, element) => {
                if (is_string_node (element)) {
                    result += element.get_string ();
                }
            });
            return result;
        }

        public Json.Object? get_object (string key) {
            unowned Json.Node? node = body.get_member (key);
            if (node != null && node.get_node_type () == Json.NodeType.OBJECT) {
                return node.get_object ();
            }
            return null;
        }

        public Packet set_string (string key, string value) {
            body.set_string_member (key, value);
            return this;
        }

        public Packet set_int (string key, int64 value) {
            body.set_int_member (key, value);
            return this;
        }

        public Packet set_bool (string key, bool value) {
            body.set_boolean_member (key, value);
            return this;
        }

        public Packet set_string_array (string key, string[] values) {
            var array = new Json.Array ();
            foreach (unowned string v in values) {
                array.add_string_element (v);
            }
            body.set_array_member (key, array);
            return this;
        }

        public string to_string () {
            return serialize ().strip ();
        }

        /* ---- helpers ---------------------------------------------------- */

        internal static bool is_string_node (Json.Node? node) {
            return node != null
                && node.get_node_type () == Json.NodeType.VALUE
                && node.get_value_type () == typeof (string);
        }

        internal static bool is_number_node (Json.Node? node) {
            if (node == null || node.get_node_type () != Json.NodeType.VALUE) {
                return false;
            }
            Type t = node.get_value_type ();
            return t == typeof (int64) || t == typeof (double);
        }
    }
}
