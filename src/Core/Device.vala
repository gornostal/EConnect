/*
 * SPDX-License-Identifier: MIT
 */
namespace EConnect.Core {

    public class Device : Object {
        public unowned Config config { get; private set; }
        public DeviceInfo info { get; private set; }
        public DeviceLink? link { get; private set; default = null; }
        public PairingHandler pairing { get; private set; }

        public string id { get { return info.id; } }
        public string name { get { return info.name; } }
        public DeviceType device_type { get { return info.device_type; } }
        public bool is_reachable { get { return link != null; } }
        public bool is_paired { get { return pairing.state == PairState.PAIRED; } }
        public PairState pair_state { get { return pairing.state; } }

        /** Live certificate if connected, else the pinned one. */
        public TlsCertificate? certificate {
            owned get {
                if (link != null) {
                    return link.peer_certificate;
                }
                return config.trusted_certificate (id);
            }
        }

        public signal void reachable_changed ();
        public signal void paired_changed ();
        public signal void pair_request ();
        public signal void pairing_failed (string reason);
        public signal void packet_received (Packet packet);

        public Device (Config config, DeviceInfo info, bool trusted) {
            this.config = config;
            this.info = info;
            pairing = new PairingHandler (this, trusted ? PairState.PAIRED : PairState.NOT_PAIRED);
            pairing.incoming_pair_request.connect (() => pair_request ());
            pairing.pairing_failed.connect ((reason) => {
                debug ("%s: pairing failed: %s", name, reason);
                pairing_failed (reason);
                paired_changed ();
            });
            pairing.pairing_successful.connect (() => {
                try {
                    config.add_trusted_device (info);
                } catch (Error e) {
                    warning ("Cannot persist pairing with %s: %s", name, e.message);
                }
                GLib.info ("Paired with %s", name);
                paired_changed ();
            });
            pairing.unpaired.connect (() => {
                config.remove_trusted_device (id);
                GLib.info ("Unpaired from %s", name);
                paired_changed ();
            });
        }

        public void add_link (DeviceLink new_link) {
            if (link != null) {
                var old = link;
                link = null;
                old.packet_received.disconnect (on_link_packet);
                old.closed.disconnect (on_link_closed);
                old.close ();
            }
            link = new_link;
            info = new_link.info;
            if (is_paired) {
                try {
                    config.update_trusted_metadata (info);
                } catch (Error e) {
                    debug ("metadata update: %s", e.message);
                }
            }
            link.packet_received.connect (on_link_packet);
            link.closed.connect (on_link_closed);
            reachable_changed ();
        }

        private void on_link_closed (DeviceLink closed_link) {
            if (closed_link != link) {
                return;
            }
            link = null;
            if (pairing.state == PairState.REQUESTED || pairing.state == PairState.REQUESTED_BY_PEER) {
                pairing.cancel_pairing ();
            }
            reachable_changed ();
        }

        private void on_link_packet (DeviceLink source, Packet packet) {
            if (packet.packet_type == Packet.TYPE_PAIR) {
                pairing.packet_received (packet);
                return;
            }
            if (!is_paired) {
                debug ("Dropping %s from unpaired device %s", packet.packet_type, name);
                return;
            }
            packet_received (packet);
        }

        public bool send_packet (Packet packet) {
            return link != null && link.send_packet (packet);
        }

        public string? verification_key () {
            return pairing.verification_key ();
        }

        public bool request_pairing () {
            return pairing.request_pairing ();
        }

        public bool accept_pairing () {
            return pairing.accept_pairing ();
        }

        public void reject_pairing () {
            pairing.cancel_pairing ();
        }

        public void unpair () {
            pairing.unpair ();
        }
    }
}
