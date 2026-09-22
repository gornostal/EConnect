/*
 * SPDX-License-Identifier: MIT
 *
 * Per-device log of received items (text, URLs, files), persisted as JSON in
 * <config>/history/<deviceId>.json. Feeds the "recent images" preview.
 */
namespace EConnect.Core {

    public enum HistoryKind {
        TEXT, URL, FILE;

        public string to_string () {
            switch (this) {
                case TEXT: return "text";
                case URL: return "url";
                default: return "file";
            }
        }

        public static HistoryKind parse (string? s) {
            switch (s) {
                case "text": return TEXT;
                case "url": return URL;
                default: return FILE;
            }
        }
    }

    public class HistoryItem : Object {
        public HistoryKind kind { get; set; }
        public string value { get; set; }          // text, url, or file path
        public int64 time_ms { get; set; }
        public bool incoming { get; set; default = true; }

        public HistoryItem (HistoryKind kind, string value, bool incoming) {
            this.kind = kind;
            this.value = value;
            this.incoming = incoming;
            time_ms = GLib.get_real_time () / 1000;
        }

        public bool is_image {
            get {
                if (kind != HistoryKind.FILE) {
                    return false;
                }
                bool uncertain;
                string? ct = ContentType.guess (value, null, out uncertain);
                return ct != null && ct.has_prefix ("image/");
            }
        }

        public bool file_exists {
            get { return kind == HistoryKind.FILE && FileUtils.test (value, FileTest.EXISTS); }
        }
    }

    public class History : Object {
        public const int MAX_ITEMS = 100;

        private unowned Config config;
        private HashTable<string, GLib.ListStore> stores = new HashTable<string, GLib.ListStore> (str_hash, str_equal);

        public signal void item_added (string device_id, HistoryItem item);

        public History (Config config) {
            this.config = config;
        }

        private File file_for (string device_id) {
            return config.config_dir.get_child ("history").get_child (device_id + ".json");
        }

        /** A ListStore of HistoryItem, newest first. */
        public GLib.ListStore for_device (string device_id) {
            var store = stores.lookup (device_id);
            if (store != null) {
                return store;
            }
            store = new GLib.ListStore (typeof (HistoryItem));
            stores.insert (device_id, store);
            load (device_id, store);
            return store;
        }

        public void add (string device_id, HistoryItem item) {
            var store = for_device (device_id);
            store.insert (0, item);
            while (store.get_n_items () > MAX_ITEMS) {
                store.remove (store.get_n_items () - 1);
            }
            save (device_id, store);
            item_added (device_id, item);
        }

        /** Newest image files that still exist, up to `limit`. */
        public HistoryItem[] recent_images (string device_id, uint limit) {
            HistoryItem[] result = {};
            var store = for_device (device_id);
            for (uint i = 0; i < store.get_n_items () && result.length < limit; i++) {
                var item = store.get_item (i) as HistoryItem;
                if (item.is_image && item.file_exists) {
                    result += item;
                }
            }
            return result;
        }

        private void load (string device_id, GLib.ListStore store) {
            var f = file_for (device_id);
            if (!f.query_exists ()) {
                return;
            }
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (f.get_path ());
                unowned Json.Node? root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.ARRAY) {
                    return;
                }
                root.get_array ().foreach_element ((arr, i, node) => {
                    if (node.get_node_type () != Json.NodeType.OBJECT) {
                        return;
                    }
                    unowned Json.Object o = node.get_object ();
                    if (!o.has_member ("value")) {
                        return;
                    }
                    var item = new HistoryItem (HistoryKind.parse (o.has_member ("kind") ? o.get_string_member ("kind") : null),
                                                o.get_string_member ("value"),
                                                o.has_member ("incoming") ? o.get_boolean_member ("incoming") : true);
                    if (o.has_member ("time")) {
                        item.time_ms = o.get_int_member ("time");
                    }
                    store.append (item);
                });
            } catch (Error e) {
                warning ("Cannot load history for %s: %s", device_id, e.message);
            }
        }

        private void save (string device_id, GLib.ListStore store) {
            var array = new Json.Array ();
            for (uint i = 0; i < store.get_n_items (); i++) {
                var item = store.get_item (i) as HistoryItem;
                var o = new Json.Object ();
                o.set_string_member ("kind", item.kind.to_string ());
                o.set_string_member ("value", item.value);
                o.set_int_member ("time", item.time_ms);
                o.set_boolean_member ("incoming", item.incoming);
                array.add_object_element (o);
            }
            var root = new Json.Node (Json.NodeType.ARRAY);
            root.set_array (array);
            var gen = new Json.Generator ();
            gen.set_root (root);
            try {
                var dir = file_for (device_id).get_parent ();
                if (!dir.query_exists ()) {
                    dir.make_directory_with_parents ();
                }
                gen.to_file (file_for (device_id).get_path ());
            } catch (Error e) {
                warning ("Cannot save history for %s: %s", device_id, e.message);
            }
        }
    }
}
