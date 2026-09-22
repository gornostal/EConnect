/*
 * SPDX-License-Identifier: MIT
 *
 * LAN transport. Mirrors kdeconnect-kde's LanLinkProvider, protocol v8:
 *
 *  A hears B's UDP identity  -> A opens TCP to B:tcpPort
 *  A writes plaintext connection packet (identity + targetDeviceId)
 *  A = TLS server, B = TLS client (yes, reversed from the TCP roles)
 *  after handshake both write their full identity, encrypted, and check
 *  that deviceId/protocolVersion did not change mid-handshake.
 */
namespace EConnect.Core {

    public class LinkProvider : Object {
        public const uint16 MIN_TCP_PORT = 1716;
        public const uint16 MAX_TCP_PORT = 1764;
        public const uint IDENTITY_TIMEOUT_MS = 3000;

        private unowned Config config;
        private SocketService? service = null;
        private GenericSet<string> connecting = new GenericSet<string> (str_hash, str_equal);

        public Discovery discovery { get; private set; }
        public uint16 tcp_port { get; private set; default = 0; }

        /** Identity we present, including plugin capabilities. Set by Daemon. */
        public DeviceInfo local_info { get; set; }

        public signal void link_established (DeviceLink link);

        public LinkProvider (Config config) {
            this.config = config;
            discovery = new Discovery (config);
            discovery.identity_received.connect (on_udp_identity);
        }

        public void start () throws Error {
            service = new SocketService ();
            for (uint16 candidate = MIN_TCP_PORT; candidate <= MAX_TCP_PORT; candidate++) {
                try {
                    service.add_inet_port (candidate, null);
                    tcp_port = candidate;
                    break;
                } catch (Error e) {
                    continue;
                }
            }
            if (tcp_port == 0) {
                throw new IOError.ADDRESS_IN_USE ("No free TCP port in %u-%u", MIN_TCP_PORT, MAX_TCP_PORT);
            }
            service.incoming.connect ((connection, source_object) => {
                handle_incoming.begin (connection);
                return true;
            });
            service.start ();
            discovery.start (tcp_port);
            discovery.broadcast ();
            info ("Listening on TCP %u, device id %s", tcp_port, config.device_id);
        }

        public void stop () {
            discovery.stop ();
            if (service != null) {
                service.stop ();
                service.close ();
                service = null;
            }
        }

        /* ---- outgoing: we heard a broadcast --------------------------------- */

        private void on_udp_identity (Packet packet, InetSocketAddress sender) {
            string id = packet.get_string ("deviceId");
            int protocol_version = (int) packet.get_int ("protocolVersion", 0);
            uint16 port = (uint16) packet.get_int ("tcpPort", 0);
            if (protocol_version < 8) {
                debug ("Ignoring %s: protocol version %d is too old", id, protocol_version);
                return;
            }
            if (port == 0) {
                return;
            }
            if (id in connecting) {
                return;
            }
            connecting.add (id);
            connect_to_device.begin (sender.get_address (), port, id, protocol_version, (obj, res) => {
                connecting.remove (id);
                try {
                    connect_to_device.end (res);
                } catch (Error e) {
                    debug ("Connection to %s at %s:%u failed: %s",
                           id, sender.get_address ().to_string (), port, e.message);
                }
            });
        }

        private async void connect_to_device (InetAddress address, uint16 port,
                                              string device_id, int protocol_version) throws Error {
            var client = new SocketClient ();
            client.timeout = 10;
            var connection = yield client.connect_async (new InetSocketAddress (address, port));
            connection.socket.timeout = 0;      // the connect timeout must not apply to idle reads
            connection.socket.keepalive = true;

            string line = local_info.to_connection_packet (device_id, Packet.PROTOCOL_VERSION).serialize ();
            size_t written;
            yield connection.output_stream.write_all_async (line.data, Priority.DEFAULT, null, out written);

            var tls = TlsServerConnection.@new (connection, config.certificate);
            tls.authentication_mode = TlsAuthenticationMode.REQUIRED;
            tls.accept_certificate.connect ((cert, errors) => accept_peer (device_id, cert));
            debug ("Starting TLS as server towards %s (I opened the TCP connection)", device_id);
            yield tls.handshake_async (Priority.DEFAULT, null);

            yield exchange_identities (tls, connection.get_remote_address () as InetSocketAddress,
                                       device_id, protocol_version);
        }

        /* ---- incoming: someone heard our broadcast ------------------------- */

        private async void handle_incoming (SocketConnection connection) {
            InetSocketAddress? remote = null;
            try {
                remote = connection.get_remote_address () as InetSocketAddress;
            } catch (Error e) {
                debug ("Incoming connection without remote address: %s", e.message);
            }
            string where = remote != null ? remote.get_address ().to_string () : "?";
            try {
                if (remote == null) {
                    throw new IOError.FAILED ("No remote address");
                }
                connection.socket.keepalive = true;
                string line = yield read_plain_line (connection.input_stream, 1000);
                var packet = Packet.parse (line);
                if (!DeviceInfo.is_valid_connection_packet (packet)) {
                    throw new PacketError.INVALID ("Invalid connection packet");
                }
                string target = packet.get_string ("targetDeviceId", "");
                if (target != "" && target != config.device_id) {
                    throw new PacketError.INVALID ("Connection meant for another device: %s", target);
                }
                int64 target_version = packet.get_int ("targetProtocolVersion", -1);
                if (target_version != -1 && target_version != Packet.PROTOCOL_VERSION) {
                    throw new PacketError.INVALID ("Connection for protocol %s, not mine", target_version.to_string ());
                }
                string device_id = packet.get_string ("deviceId");
                int protocol_version = (int) packet.get_int ("protocolVersion", 0);
                if (protocol_version < 8) {
                    throw new PacketError.INVALID ("Protocol version %d too old", protocol_version);
                }

                var tls = TlsClientConnection.@new (connection, null);
                tls.certificate = config.certificate;
                tls.accept_certificate.connect ((cert, errors) => accept_peer (device_id, cert));
                debug ("Starting TLS as client towards %s (they opened the TCP connection)", device_id);
                yield tls.handshake_async (Priority.DEFAULT, null);

                yield exchange_identities (tls, remote, device_id, protocol_version);
            } catch (Error e) {
                debug ("Incoming connection from %s dropped: %s", where, e.message);
                try {
                    connection.close ();
                } catch (Error e2) {
                    /* ignore */
                }
            }
        }

        /* ---- shared -------------------------------------------------------- */

        private bool accept_peer (string device_id, TlsCertificate cert) {
            var pinned = config.trusted_certificate (device_id);
            if (pinned == null) {
                return true;    // unpaired: any self-signed cert is fine, pairing will verify it
            }
            if (cert.is_same (pinned)) {
                return true;
            }
            warning ("Certificate of paired device %s changed. Refusing connection.", device_id);
            return false;
        }

        private async void exchange_identities (TlsConnection tls, InetSocketAddress remote,
                                                string expected_id, int expected_version) throws Error {
            string mine = local_info.to_identity_packet ().serialize ();
            size_t written;
            yield tls.output_stream.write_all_async (mine.data, Priority.DEFAULT, null, out written);

            var input = new DataInputStream (tls.input_stream);
            input.newline_type = DataStreamNewlineType.LF;
            string? line = yield read_line_timeout (input, IDENTITY_TIMEOUT_MS);
            if (line == null) {
                throw new IOError.CLOSED ("Peer closed before sending its encrypted identity");
            }
            if (line.length > Packet.MAX_IDENTITY_PACKET_SIZE) {
                throw new PacketError.INVALID ("Identity packet too large");
            }
            var identity = Packet.parse (line);
            if (!DeviceInfo.is_valid_identity_packet (identity)) {
                throw new PacketError.INVALID ("Peer does not implement protocol 8 correctly");
            }
            if (identity.get_string ("deviceId") != expected_id) {
                throw new PacketError.INVALID ("Device id changed mid-handshake: %s -> %s",
                                               expected_id, identity.get_string ("deviceId"));
            }
            if ((int) identity.get_int ("protocolVersion", 0) != expected_version) {
                throw new PacketError.INVALID ("Protocol version changed mid-handshake");
            }
            if (tls.peer_certificate == null) {
                throw new TlsError.CERTIFICATE_REQUIRED ("Peer presented no certificate");
            }

            var device_info = DeviceInfo.from_identity_packet (identity, tls.peer_certificate);
            var link = new DeviceLink (config, tls, input, device_info, remote);
            info ("Link established with %s (%s) at %s", device_info.name, device_info.id,
                  remote.get_address ().to_string ());
            link_established (link);
            link.start ();
        }

        /** Read one plaintext line byte by byte so nothing past it is buffered. */
        private async string read_plain_line (InputStream stream, uint timeout_ms) throws Error {
            var cancel = new Cancellable ();
            bool timed_out = false;
            uint timer = Timeout.add (timeout_ms, () => {
                timed_out = true;
                cancel.cancel ();
                return Source.REMOVE;
            });
            var sb = new StringBuilder ();
            uint8 buffer[1];
            try {
                while (sb.len < Packet.MAX_IDENTITY_PACKET_SIZE) {
                    ssize_t n = yield stream.read_async (buffer, Priority.DEFAULT, cancel);
                    if (n <= 0) {
                        throw new IOError.CLOSED ("Peer closed before sending a connection packet");
                    }
                    if (buffer[0] == '\n') {
                        return sb.str;
                    }
                    sb.append_c ((char) buffer[0]);
                }
                throw new PacketError.INVALID ("Connection packet too large");
            } catch (IOError e) {
                if (timed_out) {
                    throw new IOError.TIMED_OUT ("Peer sent no connection packet within %u ms", timeout_ms);
                }
                throw e;
            } finally {
                if (!timed_out) {
                    Source.remove (timer);
                }
            }
        }

        private async string? read_line_timeout (DataInputStream input, uint timeout_ms) throws Error {
            var cancel = new Cancellable ();
            bool timed_out = false;
            uint timer = Timeout.add (timeout_ms, () => {
                timed_out = true;
                cancel.cancel ();
                return Source.REMOVE;
            });
            try {
                return yield input.read_line_async (Priority.DEFAULT, cancel);
            } catch (IOError e) {
                if (timed_out) {
                    throw new IOError.TIMED_OUT ("Peer sent no encrypted identity within %u ms", timeout_ms);
                }
                throw e;
            } finally {
                if (!timed_out) {
                    Source.remove (timer);
                }
            }
        }
    }
}
