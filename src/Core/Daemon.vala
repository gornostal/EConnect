/*
 * SPDX-License-Identifier: MIT
 *
 * Owns the transport, the device table and the plugin list.
 */
namespace EConnect.Core {

    public class Daemon : Object {
        public Config config { get; private set; }
        public LinkProvider link_provider { get; private set; }

        private HashTable<string, Device> devices = new HashTable<string, Device> (str_hash, str_equal);
        private GLib.List<Plugins.Plugin> plugins = new GLib.List<Plugins.Plugin> ();
        private uint rebroadcast_id = 0;

        public signal void device_added (Device device);
        public signal void device_removed (Device device);
        public signal void device_changed (Device device);

        public Daemon (Config config) {
            this.config = config;
            link_provider = new LinkProvider (config);
            link_provider.link_established.connect (on_link_established);
        }

        public void add_plugin (Plugins.Plugin plugin) {
            plugins.append (plugin);
            plugin.daemon = this;
        }

        public unowned GLib.List<Plugins.Plugin> get_plugins () {
            return plugins;
        }

        public void start () throws Error {
            /* Announce remembered devices first so listeners are already attached. */
            foreach (var info in config.load_trusted_devices ()) {
                if (devices.lookup (info.id) == null) {
                    add_device (new Device (config, info, true));
                }
            }
            link_provider.local_info = build_local_info ();
            link_provider.start ();
            rebroadcast_id = Timeout.add_seconds (20, () => {
                bool anyone_unreachable = false;
                devices.foreach ((id, dev) => {
                    if (!dev.is_reachable) {
                        anyone_unreachable = true;
                    }
                });
                if (anyone_unreachable || devices.size () == 0) {
                    link_provider.discovery.broadcast ();
                }
                return Source.CONTINUE;
            });
        }

        public void stop () {
            if (rebroadcast_id != 0) {
                Source.remove (rebroadcast_id);
                rebroadcast_id = 0;
            }
            /* Closing a link may remove an unpaired device, so iterate over a copy. */
            foreach (var dev in devices.get_values ()) {
                if (dev.link != null) {
                    dev.link.close ();
                }
            }
            link_provider.stop ();
        }

        public void refresh () {
            link_provider.discovery.broadcast ();
        }

        private DeviceInfo build_local_info () {
            var incoming = new GenericSet<string> (str_hash, str_equal);
            var outgoing = new GenericSet<string> (str_hash, str_equal);
            foreach (var plugin in plugins) {
                foreach (string t in plugin.incoming_types) {
                    incoming.add (t);
                }
                foreach (string t in plugin.outgoing_types) {
                    outgoing.add (t);
                }
            }
            string[] inc = {};
            string[] outg = {};
            incoming.foreach ((t) => { inc += t; });
            outgoing.foreach ((t) => { outg += t; });
            return config.local_device_info (inc, outg);
        }

        public GLib.List<weak Device> get_devices () {
            return devices.get_values ();
        }

        public Device? get_device (string id) {
            return devices.lookup (id);
        }

        private void add_device (Device device) {
            devices.insert (device.id, device);
            device.packet_received.connect (dispatch);
            device.reachable_changed.connect (on_device_reachable_changed);
            device.paired_changed.connect (on_device_paired_changed);
            device_added (device);
        }

        private void on_link_established (DeviceLink link) {
            var device = devices.lookup (link.info.id);
            if (device == null) {
                device = new Device (config, link.info, config.is_trusted (link.info.id));
                add_device (device);
            }
            device.add_link (link);
        }

        private void on_device_reachable_changed (Device device) {
            if (device.is_reachable && device.is_paired) {
                foreach (var plugin in plugins) {
                    plugin.device_connected (device);
                }
            }
            if (!device.is_reachable && !device.is_paired) {
                devices.remove (device.id);
                device_removed (device);
                return;
            }
            device_changed (device);
        }

        private void on_device_paired_changed (Device device) {
            if (device.is_reachable && device.is_paired) {
                foreach (var plugin in plugins) {
                    plugin.device_connected (device);
                }
            }
            device_changed (device);
        }

        private void dispatch (Device device, Packet packet) {
            bool handled = false;
            foreach (var plugin in plugins) {
                if (packet.packet_type in plugin.incoming_types) {
                    plugin.handle_packet (device, packet);
                    handled = true;
                }
            }
            if (!handled) {
                debug ("No plugin for %s from %s", packet.packet_type, device.name);
            }
        }
    }
}
