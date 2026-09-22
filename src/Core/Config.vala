/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Persistent state:
 *   <config>/privateKey.pem, certificate.pem, deviceId, name
 *   <config>/trusted_devices/<id>/certificate.pem + device.ini
 */
namespace EConnect.Core {

    public class Config : Object {
        public string device_id { get; private set; }
        public string device_name { get; set; }
        public DeviceType device_type { get; set; default = DeviceType.DESKTOP; }
        public TlsCertificate certificate { get; private set; }
        public uint8[] public_key_der;
        public File config_dir { get; private set; }
        public File trusted_dir { get; private set; }

        public signal void trusted_devices_changed ();

        public Config (string? base_dir = null, string? name_override = null) throws Error {
            string dir = base_dir ?? Path.build_filename (Environment.get_user_config_dir (), APP_ID);
            config_dir = File.new_for_path (dir);
            trusted_dir = config_dir.get_child ("trusted_devices");
            ensure_dir (config_dir);
            ensure_dir (trusted_dir);
            FileUtils.chmod (config_dir.get_path (), 0700);

            load_or_generate_identity ();

            var name_file = config_dir.get_child ("name");
            if (name_override != null) {
                device_name = DeviceInfo.filter_name (name_override);
            } else if (name_file.query_exists ()) {
                string contents;
                FileUtils.get_contents (name_file.get_path (), out contents);
                device_name = DeviceInfo.filter_name (contents.strip ());
            }
            if (device_name == null || device_name == "") {
                device_name = DeviceInfo.filter_name (Environment.get_host_name ());
            }
            if (device_name == "") {
                device_name = "elementary OS";
            }
        }

        public void save_name (string name) throws Error {
            device_name = DeviceInfo.filter_name (name);
            FileUtils.set_contents (config_dir.get_child ("name").get_path (), device_name);
        }

        private static void ensure_dir (File dir) throws Error {
            if (!dir.query_exists ()) {
                dir.make_directory_with_parents ();
            }
        }

        private void load_or_generate_identity () throws Error {
            var key_file = config_dir.get_child ("privateKey.pem");
            var cert_file = config_dir.get_child ("certificate.pem");
            var id_file = config_dir.get_child ("deviceId");

            bool have_all = key_file.query_exists () && cert_file.query_exists () && id_file.query_exists ();
            if (!have_all) {
                string id = Certificate.new_device_id ();
                info ("Generating a new device identity %s", id);
                Certificate.generate (key_file.get_path (), cert_file.get_path (), id);
                FileUtils.set_contents (id_file.get_path (), id);
                /* A new certificate invalidates every existing pairing. */
                foreach (var dev in load_trusted_devices ()) {
                    remove_trusted_device (dev.id);
                }
            }

            string id_contents;
            FileUtils.get_contents (id_file.get_path (), out id_contents);
            device_id = id_contents.strip ();
            if (!DeviceInfo.is_valid_device_id (device_id)) {
                throw new IOError.INVALID_DATA ("Stored device id '%s' is invalid", device_id);
            }
            certificate = new TlsCertificate.from_files (cert_file.get_path (), key_file.get_path ());
            public_key_der = Certificate.public_key_der (certificate);
        }

        public DeviceInfo local_device_info (string[] incoming, string[] outgoing) {
            var info = new DeviceInfo (device_id, device_name, device_type);
            info.protocol_version = Packet.PROTOCOL_VERSION;
            info.incoming_capabilities = incoming;
            info.outgoing_capabilities = outgoing;
            info.certificate = certificate;
            return info;
        }

        /* ---- trusted devices -------------------------------------------- */

        public bool is_trusted (string id) {
            return trusted_dir.get_child (id).get_child ("certificate.pem").query_exists ();
        }

        public TlsCertificate? trusted_certificate (string id) {
            var f = trusted_dir.get_child (id).get_child ("certificate.pem");
            if (!f.query_exists ()) {
                return null;
            }
            try {
                return new TlsCertificate.from_file (f.get_path ());
            } catch (Error e) {
                warning ("Cannot read trusted certificate for %s: %s", id, e.message);
                return null;
            }
        }

        public DeviceInfo[] load_trusted_devices () {
            DeviceInfo[] result = {};
            try {
                var it = trusted_dir.enumerate_children ("standard::name,standard::type",
                                                         FileQueryInfoFlags.NONE);
                FileInfo? fi;
                while ((fi = it.next_file ()) != null) {
                    if (fi.get_file_type () != FileType.DIRECTORY) {
                        continue;
                    }
                    var dev = load_trusted_device (fi.get_name ());
                    if (dev != null) {
                        result += dev;
                    }
                }
            } catch (Error e) {
                warning ("Cannot enumerate trusted devices: %s", e.message);
            }
            return result;
        }

        private DeviceInfo? load_trusted_device (string id) {
            if (!DeviceInfo.is_valid_device_id (id)) {
                return null;
            }
            var cert = trusted_certificate (id);
            if (cert == null) {
                return null;
            }
            var kf = new KeyFile ();
            string name = id;
            var type = DeviceType.PHONE;
            string[] incoming = {};
            string[] outgoing = {};
            try {
                kf.load_from_file (trusted_dir.get_child (id).get_child ("device.ini").get_path (),
                                   KeyFileFlags.NONE);
                name = kf.get_string ("Device", "name");
                type = DeviceType.parse (kf.get_string ("Device", "type"));
                if (kf.has_key ("Device", "incoming")) {
                    incoming = kf.get_string_list ("Device", "incoming");
                }
                if (kf.has_key ("Device", "outgoing")) {
                    outgoing = kf.get_string_list ("Device", "outgoing");
                }
            } catch (Error e) {
                debug ("No metadata for trusted device %s: %s", id, e.message);
            }
            var info = new DeviceInfo (id, name, type);
            info.certificate = cert;
            info.incoming_capabilities = incoming;
            info.outgoing_capabilities = outgoing;
            info.protocol_version = Packet.PROTOCOL_VERSION;
            return info;
        }

        public void add_trusted_device (DeviceInfo dev) throws Error {
            if (dev.certificate == null) {
                throw new IOError.INVALID_ARGUMENT ("Cannot trust a device without a certificate");
            }
            var dir = trusted_dir.get_child (dev.id);
            ensure_dir (dir);
            FileUtils.set_contents (dir.get_child ("certificate.pem").get_path (),
                                    dev.certificate.certificate_pem);
            update_trusted_metadata (dev);
            trusted_devices_changed ();
        }

        public void update_trusted_metadata (DeviceInfo dev) throws Error {
            var dir = trusted_dir.get_child (dev.id);
            if (!dir.query_exists ()) {
                return;
            }
            var kf = new KeyFile ();
            kf.set_string ("Device", "name", dev.name);
            kf.set_string ("Device", "type", dev.device_type.to_string ());
            kf.set_string_list ("Device", "incoming", dev.incoming_capabilities);
            kf.set_string_list ("Device", "outgoing", dev.outgoing_capabilities);
            kf.save_to_file (dir.get_child ("device.ini").get_path ());
        }

        public void remove_trusted_device (string id) {
            var dir = trusted_dir.get_child (id);
            try {
                foreach (string f in new string[] { "certificate.pem", "device.ini" }) {
                    var child = dir.get_child (f);
                    if (child.query_exists ()) {
                        child.delete ();
                    }
                }
                if (dir.query_exists ()) {
                    dir.delete ();
                }
            } catch (Error e) {
                warning ("Cannot remove trusted device %s: %s", id, e.message);
            }
            trusted_devices_changed ();
        }
    }
}
