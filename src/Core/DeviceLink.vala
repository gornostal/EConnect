/*
 * SPDX-License-Identifier: MIT
 *
 * One established, authenticated TLS connection to a remote device.
 * Reads newline-delimited packets and queues outgoing writes.
 */
namespace EConnect.Core {

    public class DeviceLink : Object {
        public const uint16 MIN_PAYLOAD_PORT = 1739;
        public const uint16 MAX_PAYLOAD_PORT = 1764;
        public const uint PAYLOAD_ACCEPT_TIMEOUT_SECONDS = 60;

        public DeviceInfo info { get; private set; }
        public InetSocketAddress remote_address { get; private set; }
        public bool is_open { get; private set; default = true; }

        public TlsCertificate peer_certificate {
            get { return info.certificate; }
        }

        private unowned Config config;
        private TlsConnection tls;
        private DataInputStream input;
        private OutputStream output;
        private Cancellable cancellable = new Cancellable ();
        private GLib.Queue<string> outbox = new GLib.Queue<string> ();
        private bool writing = false;

        public signal void packet_received (Packet packet);
        public signal void closed ();

        public DeviceLink (Config config, TlsConnection tls, DataInputStream input,
                           DeviceInfo info, InetSocketAddress remote_address) {
            this.config = config;
            this.tls = tls;
            this.input = input;
            this.output = tls.output_stream;
            this.info = info;
            this.remote_address = remote_address;
        }

        public void start () {
            read_loop.begin ();
        }

        private async void read_loop () {
            while (is_open) {
                string? line = null;
                try {
                    line = yield input.read_line_async (Priority.DEFAULT, cancellable);
                } catch (Error e) {
                    if (!(e is IOError.CANCELLED)) {
                        debug ("Link to %s read error: %s", info.name, e.message);
                    }
                    break;
                }
                if (line == null) {
                    break;
                }
                if (line.strip () == "") {
                    continue;
                }
                Packet packet;
                try {
                    packet = Packet.parse (line);
                } catch (Error e) {
                    warning ("Bad packet from %s: %s", info.name, e.message);
                    continue;
                }
                if (packet.has_payload) {
                    packet.payload_host = remote_address.get_address ();
                }
                debug ("<- %s: %s", info.name, packet.to_string ());
                packet_received (packet);
            }
            close ();
        }

        public bool send_packet (Packet packet) {
            if (!is_open) {
                return false;
            }
            debug ("-> %s: %s", info.name, packet.to_string ());
            outbox.push_tail (packet.serialize ());
            if (!writing) {
                flush.begin ();
            }
            return true;
        }

        private async void flush () {
            writing = true;
            while (is_open && !outbox.is_empty ()) {
                string data = outbox.pop_head ();
                try {
                    size_t written;
                    yield output.write_all_async (data.data, Priority.DEFAULT, cancellable, out written);
                } catch (Error e) {
                    if (!(e is IOError.CANCELLED)) {
                        warning ("Link to %s write error: %s", info.name, e.message);
                    }
                    close ();
                }
            }
            writing = false;
        }

        public void close () {
            if (!is_open) {
                return;
            }
            is_open = false;
            cancellable.cancel ();
            tls.close_async.begin (Priority.DEFAULT, null, (obj, res) => {
                try {
                    tls.close_async.end (res);
                } catch (Error e) {
                    debug ("closing link: %s", e.message);
                }
            });
            closed ();
        }

        /* ---- payloads ---------------------------------------------------- */

        private bool accept_peer (TlsCertificate cert) {
            return cert.is_same (peer_certificate);
        }

        /**
         * Connect to the port advertised in a received packet and return the
         * TLS stream carrying the payload. The caller reads payload_size bytes.
         */
        public async IOStream open_payload (Packet packet, Cancellable? cancel = null) throws Error {
            if (!packet.has_payload || packet.payload_transfer_info == null
                || !packet.payload_transfer_info.has_member ("port")) {
                throw new IOError.INVALID_ARGUMENT ("Packet carries no payload port");
            }
            uint16 port = (uint16) packet.payload_transfer_info.get_int_member ("port");
            var client = new SocketClient ();
            client.timeout = 15;
            var conn = yield client.connect_async (
                new InetSocketAddress (remote_address.get_address (), port), cancel);
            conn.socket.timeout = 0;

            var client_tls = TlsClientConnection.@new (conn, null);
            client_tls.certificate = config.certificate;
            client_tls.accept_certificate.connect ((cert, errors) => accept_peer (cert));
            yield client_tls.handshake_async (Priority.DEFAULT, cancel);
            return client_tls;
        }

        /**
         * Send a packet whose payload is read from `data`. Opens a TLS server
         * socket on 1739-1764, advertises it in payloadTransferInfo and waits
         * for the peer to fetch the bytes.
         */
        public async void send_payload_packet (Packet packet, InputStream data, int64 size,
                                               Cancellable? cancel = null) throws Error {
            var listener = new SocketListener ();
            uint16 port = 0;
            for (uint16 candidate = MIN_PAYLOAD_PORT; candidate <= MAX_PAYLOAD_PORT; candidate++) {
                try {
                    listener.add_inet_port (candidate, null);
                    port = candidate;
                    break;
                } catch (Error e) {
                    continue;
                }
            }
            if (port == 0) {
                throw new IOError.ADDRESS_IN_USE ("No free payload port in %u-%u",
                                                  MIN_PAYLOAD_PORT, MAX_PAYLOAD_PORT);
            }

            packet.payload_size = size;
            var transfer_info = new Json.Object ();
            transfer_info.set_int_member ("port", port);
            packet.payload_transfer_info = transfer_info;

            if (!send_packet (packet)) {
                listener.close ();
                throw new IOError.CLOSED ("Link is closed");
            }

            var accept_cancel = new Cancellable ();
            bool timed_out = false;
            uint timer = Timeout.add_seconds (PAYLOAD_ACCEPT_TIMEOUT_SECONDS, () => {
                timed_out = true;
                accept_cancel.cancel ();
                return Source.REMOVE;
            });
            if (cancel != null) {
                cancel.connect (() => accept_cancel.cancel ());
            }

            SocketConnection? conn = null;
            try {
                conn = yield listener.accept_async (accept_cancel);
            } catch (Error e) {
                if (timed_out) {
                    throw new IOError.TIMED_OUT ("%s never fetched the payload", info.name);
                }
                throw e;
            } finally {
                if (!timed_out) {
                    Source.remove (timer);
                }
                listener.close ();
            }

            var server_tls = TlsServerConnection.@new (conn, config.certificate);
            server_tls.authentication_mode = TlsAuthenticationMode.REQUIRED;
            server_tls.accept_certificate.connect ((cert, errors) => accept_peer (cert));
            yield server_tls.handshake_async (Priority.DEFAULT, cancel);
            yield server_tls.output_stream.splice_async (
                data, OutputStreamSpliceFlags.CLOSE_SOURCE, Priority.DEFAULT, cancel);
            yield server_tls.close_async (Priority.DEFAULT, cancel);
        }
    }
}
