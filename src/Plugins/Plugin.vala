/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
namespace EConnect.Plugins {

    public abstract class Plugin : Object {
        public weak Core.Daemon? daemon { get; set; default = null; }

        /** Packet types this plugin accepts. */
        public abstract string[] incoming_types { owned get; }
        /** Packet types this plugin may send. */
        public abstract string[] outgoing_types { owned get; }

        public virtual void handle_packet (Core.Device device, Core.Packet packet) {
        }

        /** A paired device just became reachable (or a reachable one got paired). */
        public virtual void device_connected (Core.Device device) {
        }
    }
}
