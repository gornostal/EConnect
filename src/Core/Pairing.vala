/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Pairing state machine, matching kdeconnect-kde's PairingHandler.
 */
namespace EConnect.Core {

    public enum PairState {
        NOT_PAIRED,
        REQUESTED,          // we asked, waiting for the peer
        REQUESTED_BY_PEER,  // they asked, waiting for the user
        PAIRED;

        public string to_string () {
            switch (this) {
                case REQUESTED: return "pairing requested";
                case REQUESTED_BY_PEER: return "pairing requested by device";
                case PAIRED: return "paired";
                default: return "not paired";
            }
        }
    }

    public class PairingHandler : Object {
        public const uint TIMEOUT_SECONDS = 30;
        public const int64 ALLOWED_CLOCK_SKEW_SECONDS = 1800;

        public PairState state { get; private set; }

        private unowned Device device;
        private int64 pairing_timestamp = 0;
        private uint timeout_id = 0;

        public signal void incoming_pair_request ();
        public signal void pairing_successful ();
        public signal void pairing_failed (string reason);
        public signal void unpaired ();

        public PairingHandler (Device device, PairState initial_state) {
            this.device = device;
            this.state = initial_state;
        }

        private void start_timeout () {
            stop_timeout ();
            timeout_id = Timeout.add_seconds (TIMEOUT_SECONDS, () => {
                timeout_id = 0;
                on_timeout ();
                return Source.REMOVE;
            });
        }

        private void stop_timeout () {
            if (timeout_id != 0) {
                Source.remove (timeout_id);
                timeout_id = 0;
            }
        }

        private Packet pair_packet (bool pair) {
            return new Packet (Packet.TYPE_PAIR).set_bool ("pair", pair);
        }

        public void packet_received (Packet packet) {
            bool wants_pair = packet.get_bool ("pair", false);
            if (wants_pair) {
                switch (state) {
                    case PairState.REQUESTED:
                        stop_timeout ();
                        pairing_done ();
                        break;
                    case PairState.REQUESTED_BY_PEER:
                        debug ("Ignoring second pairing request before the first one timed out");
                        break;
                    case PairState.PAIRED:
                    case PairState.NOT_PAIRED:
                        if (state == PairState.PAIRED) {
                            warning ("Received pairing request from a device we already trusted.");
                            state = PairState.NOT_PAIRED;
                            unpaired ();
                        }
                        pairing_timestamp = packet.get_int ("timestamp", -1);
                        if (pairing_timestamp == -1) {
                            state = PairState.NOT_PAIRED;
                            pairing_failed ("Pairing request without timestamp (protocol < 8)");
                            return;
                        }
                        int64 now = GLib.get_real_time () / 1000000;
                        if ((pairing_timestamp - now).abs () > ALLOWED_CLOCK_SKEW_SECONDS) {
                            state = PairState.NOT_PAIRED;
                            pairing_failed ("Device clocks are out of sync");
                            return;
                        }
                        state = PairState.REQUESTED_BY_PEER;
                        start_timeout ();
                        incoming_pair_request ();
                        break;
                }
            } else {
                stop_timeout ();
                switch (state) {
                    case PairState.NOT_PAIRED:
                        debug ("Ignoring unpair request for already unpaired device");
                        break;
                    case PairState.REQUESTED:
                    case PairState.REQUESTED_BY_PEER:
                        state = PairState.NOT_PAIRED;
                        pairing_failed ("Canceled by other peer");
                        break;
                    case PairState.PAIRED:
                        state = PairState.NOT_PAIRED;
                        unpaired ();
                        break;
                }
            }
        }

        public bool request_pairing () {
            stop_timeout ();
            if (state == PairState.PAIRED) {
                warning ("%s: request_pairing on an already paired device", device.name);
                return false;
            }
            if (state == PairState.REQUESTED_BY_PEER) {
                debug ("%s: pairing already started by the other end, accepting", device.name);
                return accept_pairing ();
            }
            if (!device.is_reachable) {
                pairing_failed ("%s: device not reachable".printf (device.name));
                return false;
            }
            state = PairState.REQUESTED;
            start_timeout ();
            pairing_timestamp = GLib.get_real_time () / 1000000;
            var packet = pair_packet (true).set_int ("timestamp", pairing_timestamp);
            if (!device.send_packet (packet)) {
                stop_timeout ();
                state = PairState.NOT_PAIRED;
                pairing_failed ("%s: device not reachable".printf (device.name));
                return false;
            }
            return true;
        }

        public bool accept_pairing () {
            if (state == PairState.PAIRED) {
                return true;
            }
            if (state != PairState.REQUESTED_BY_PEER) {
                warning ("Cannot accept pairing without a pairing request");
                return false;
            }
            stop_timeout ();
            if (device.send_packet (pair_packet (true))) {
                pairing_done ();
                return true;
            }
            state = PairState.NOT_PAIRED;
            pairing_failed ("Device not reachable");
            return false;
        }

        public void cancel_pairing () {
            if (state != PairState.REQUESTED && state != PairState.REQUESTED_BY_PEER) {
                return;
            }
            stop_timeout ();
            state = PairState.NOT_PAIRED;
            device.send_packet (pair_packet (false));
            pairing_failed ("Cancelled by user");
        }

        public void unpair () {
            stop_timeout ();
            state = PairState.NOT_PAIRED;
            device.send_packet (pair_packet (false));
            unpaired ();
        }

        private void on_timeout () {
            device.send_packet (pair_packet (false));
            state = PairState.NOT_PAIRED;
            pairing_failed ("Timed out");
        }

        private void pairing_done () {
            state = PairState.PAIRED;
            pairing_successful ();
        }

        /**
         * SHA256(max(pubA, pubB) ‖ min(pubA, pubB) ‖ decimal timestamp),
         * first 8 hex chars, uppercase. Same on both devices.
         */
        public string? verification_key () {
            if (state != PairState.REQUESTED && state != PairState.REQUESTED_BY_PEER) {
                return null;
            }
            var peer_cert = device.certificate;
            if (peer_cert == null) {
                return null;
            }
            uint8[] a = device.config.public_key_der;
            uint8[] b;
            try {
                b = Certificate.public_key_der (peer_cert);
            } catch (Error e) {
                warning ("Cannot extract peer public key: %s", e.message);
                return null;
            }
            if (Der.compare (a, b) < 0) {
                uint8[] tmp = a;
                a = b;
                b = tmp;
            }
            var cs = new Checksum (ChecksumType.SHA256);
            cs.update (a, a.length);
            cs.update (b, b.length);
            string ts = pairing_timestamp.to_string ();
            cs.update (ts.data, ts.length);
            return cs.get_string ().substring (0, 8).up ();
        }
    }
}
