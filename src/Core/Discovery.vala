/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * UDP discovery on port 1716. Broadcasts our identity and reports identity
 * packets from other devices.
 */
namespace EConnect.Core {

    public class Discovery : Object {
        public const uint16 UDP_PORT = 1716;

        private unowned Config config;
        private Socket? socket = null;
        private Source? source = null;
        private uint16 tcp_port = 0;
        private InetSocketAddress broadcast_addr;

        /** A valid identity packet arrived from another device. */
        public signal void identity_received (Packet packet, InetSocketAddress sender);

        public bool has_discovery_port { get; private set; default = false; }

        public Discovery (Config config) {
            this.config = config;
            broadcast_addr = new InetSocketAddress (new InetAddress.from_string ("255.255.255.255"), UDP_PORT);
        }

        public void start (uint16 tcp_port) throws Error {
            this.tcp_port = tcp_port;
            socket = new Socket (SocketFamily.IPV4, SocketType.DATAGRAM, SocketProtocol.UDP);
            socket.broadcast = true;
            socket.blocking = false;
            var any = new InetAddress.any (SocketFamily.IPV4);
            try {
                socket.bind (new InetSocketAddress (any, UDP_PORT), true);
                has_discovery_port = true;
            } catch (Error e) {
                warning ("UDP port %u is busy (%s); other devices can still find us through our own broadcasts",
                         UDP_PORT, e.message);
                socket.bind (new InetSocketAddress (any, 0), true);
            }

            source = socket.create_source (IOCondition.IN, null);
            ((SocketSource) source).set_callback ((s, cond) => {
                on_readable ();
                return Source.CONTINUE;
            });
            source.attach (MainContext.default ());
        }

        public void stop () {
            if (source != null) {
                source.destroy ();
                source = null;
            }
            if (socket != null) {
                try {
                    socket.close ();
                } catch (Error e) {
                    debug ("closing discovery socket: %s", e.message);
                }
                socket = null;
            }
        }

        private void on_readable () {
            if (socket == null) {
                return;
            }
            uint8 buffer[8192];
            while (true) {
                SocketAddress from;
                ssize_t n;
                try {
                    n = socket.receive_from (out from, buffer);
                } catch (IOError e) {
                    if (!(e is IOError.WOULD_BLOCK)) {
                        warning ("UDP receive failed: %s", e.message);
                    }
                    return;
                } catch (Error e) {
                    warning ("UDP receive failed: %s", e.message);
                    return;
                }
                if (n <= 0) {
                    return;
                }
                var sender = from as InetSocketAddress;
                if (sender == null || sender.get_address ().is_loopback) {
                    continue;
                }
                string text = ((string) buffer).substring (0, (long) n);
                Packet packet;
                try {
                    packet = Packet.parse (text);
                } catch (Error e) {
                    debug ("Ignoring UDP datagram from %s: %s", sender.get_address ().to_string (), e.message);
                    continue;
                }
                if (!DeviceInfo.is_valid_udp_discovery_packet (packet)) {
                    continue;
                }
                if (packet.get_string ("deviceId") == config.device_id) {
                    continue;   // our own broadcast
                }
                identity_received (packet, sender);
            }
        }

        private Packet discovery_packet () {
            var info = new DeviceInfo (config.device_id, config.device_name, config.device_type);
            info.protocol_version = Packet.PROTOCOL_VERSION;
            return info.to_udp_discovery_packet (tcp_port);
        }

        /** Announce ourselves to the whole LAN. */
        public void broadcast () {
            send_to_address (broadcast_addr);
        }

        /** Announce ourselves to one host (manual "add device by IP"). */
        public void send_to (InetAddress address) {
            send_to_address (new InetSocketAddress (address, UDP_PORT));
        }

        private void send_to_address (InetSocketAddress target) {
            if (socket == null) {
                return;
            }
            string data = discovery_packet ().serialize ();
            try {
                socket.send_to (target, data.data);
            } catch (Error e) {
                warning ("UDP send to %s failed: %s", target.get_address ().to_string (), e.message);
            }
        }
    }
}
