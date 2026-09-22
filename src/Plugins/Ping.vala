/*
 * SPDX-License-Identifier: MIT
 */
namespace EConnect.Plugins {

    public class Ping : Plugin {
        public override string[] incoming_types {
            owned get { return { Core.Packet.TYPE_PING }; }
        }

        public override string[] outgoing_types {
            owned get { return { Core.Packet.TYPE_PING }; }
        }

        public signal void ping_received (Core.Device device, string? message);

        public override void handle_packet (Core.Device device, Core.Packet packet) {
            ping_received (device, packet.get_string ("message"));
        }

        public bool send_ping (Core.Device device, string? message = null) {
            var packet = new Core.Packet (Core.Packet.TYPE_PING);
            if (message != null && message != "") {
                packet.set_string ("message", message);
            }
            return device.send_packet (packet);
        }
    }
}
