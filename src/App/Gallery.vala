/*
 * SPDX-License-Identifier: MIT
 *
 * Pulls the newest photos and screenshots from an Android phone through the
 * KDE Connect SFTP plugin, mounting it with GVFS and caching thumbnails in
 * ~/.cache/<app>/gallery/<deviceId>/. Needs the host gvfsd, which under Flatpak
 * means --filesystem=xdg-run/gvfsd; without it the pull fails and the device
 * page keeps working without a gallery.
 */
namespace EConnect.App {

    /** Answers GVFS prompts with the credentials the phone sent us. */
    private class SftpMountOperation : MountOperation {
        private string user;
        private string pass;

        public SftpMountOperation (string user, string pass) {
            this.user = user;
            this.pass = pass;
        }

        public override void ask_password (string message, string default_user,
                                           string default_domain, AskPasswordFlags flags) {
            username = user;
            password = pass;
            password_save = PasswordSave.NEVER;
            anonymous = false;
            reply (MountOperationResult.HANDLED);
        }

        public override void ask_question (string message, [CCode (array_length = false, array_null_terminated = true)] string[] choices) {
            /* Unknown host key prompt: pick the "log in anyway" style choice. */
            int pick = 0;
            for (int i = 0; choices[i] != null; i++) {
                string c = choices[i].down ();
                if (c.contains ("anyway") || c.contains ("connect") || c.contains ("log in")) {
                    pick = i;
                    break;
                }
            }
            debug ("GVFS asks: %s -> %s", message.replace ("\n", " "), choices[pick]);
            choice = pick;
            reply (MountOperationResult.HANDLED);
        }
    }

    public class Gallery : Object {
        public const uint MAX_IMAGES = 5;
        public const uint IMAGE_LIMIT_PER_FOLDER = 40;

        private const string[] CANDIDATE_FOLDERS = {
            "DCIM/Camera", "DCIM/Screenshots", "Pictures/Screenshots", "Pictures", "Download"
        };

        private Application app;
        private File cache_root;
        private HashTable<string, GenericArray<Core.HistoryItem>> items =
            new HashTable<string, GenericArray<Core.HistoryItem>> (str_hash, str_equal);
        private GenericSet<string> busy = new GenericSet<string> (str_hash, str_equal);

        public signal void updated (string device_id);
        public signal void failed (string device_id, string reason);
        public signal void busy_changed (string device_id, bool busy);

        public Gallery (Application app) {
            this.app = app;
            cache_root = File.new_for_path (Path.build_filename (Environment.get_user_cache_dir (), APP_ID, "gallery"));
            app.sftp.ready.connect ((device, info) => fetch.begin (device, info));
            app.sftp.failed.connect ((device, reason) => {
                busy.remove (device.id);
                busy_changed (device.id, false);
                failed (device.id, reason);
            });
        }

        public bool is_busy (string device_id) {
            return device_id in busy;
        }

        /** Cached items for a device, newest first. */
        public Core.HistoryItem[] get_items (string device_id) {
            var list = items.lookup (device_id);
            if (list == null) {
                load_cache (device_id);
                list = items.lookup (device_id);
            }
            Core.HistoryItem[] result = {};
            if (list != null) {
                for (uint i = 0; i < list.length; i++) {
                    result += list[i];
                }
            }
            return result;
        }

        /** Kick off a refresh: ask the phone for SFTP access, then pull images. */
        public bool refresh (Core.Device device) {
            if (!Plugins.Sftp.supported_by (device) || !device.is_paired || !device.is_reachable) {
                return false;
            }
            if (device.id in busy) {
                return true;
            }
            busy.add (device.id);
            busy_changed (device.id, true);
            if (!app.sftp.request_browsing (device)) {
                busy.remove (device.id);
                busy_changed (device.id, false);
                return false;
            }
            return true;
        }

        private File cache_dir (string device_id) {
            return cache_root.get_child (device_id);
        }

        private void load_cache (string device_id) {
            var list = new GenericArray<Core.HistoryItem> ();
            var dir = cache_dir (device_id);
            try {
                if (dir.query_exists ()) {
                    var it = dir.enumerate_children ("standard::name,time::modified", FileQueryInfoFlags.NONE);
                    FileInfo? fi;
                    while ((fi = it.next_file ()) != null) {
                        var item = new Core.HistoryItem (Core.HistoryKind.FILE, dir.get_child (fi.get_name ()).get_path (), true);
                        var dt = fi.get_modification_date_time ();
                        item.time_ms = dt != null ? dt.to_unix () * 1000 : 0;
                        list.add (item);
                    }
                }
            } catch (Error e) {
                debug ("gallery cache: %s", e.message);
            }
            list.sort ((a, b) => (int) (b.time_ms - a.time_ms).clamp (-1, 1));
            items.insert (device_id, list);
        }

        private class Candidate {
            public File file;
            public string name;
            public int64 mtime_ms;
            public int64 size;
        }

        private async void fetch (Core.Device device, Plugins.SftpInfo info) {
            string id = device.id;
            var root = File.new_for_uri (info.uri ());
            Mount? mount = null;
            try {
                var op = new SftpMountOperation (info.user, info.password);
                try {
                    yield root.mount_enclosing_volume (MountMountFlags.NONE, op, null);
                } catch (IOError e) {
                    if (e is IOError.NOT_SUPPORTED) {
                        /* No GVFS sftp backend reachable. Inside a Flatpak this
                         * means the sandbox cannot see the host gvfsd. */
                        throw new IOError.NOT_SUPPORTED (
                            _("Cannot browse the phone: SFTP support is unavailable on this system."));
                    }
                    if (!(e is IOError.ALREADY_MOUNTED)) {
                        throw e;
                    }
                }
                try {
                    mount = yield root.find_enclosing_mount_async ();
                } catch (Error e) {
                    debug ("find mount: %s", e.message);
                }

                var candidates = new GenericArray<Candidate> ();
                string[] roots = info.roots.length > 0 ? info.roots : new string[] { "/" };
                foreach (string phone_root in roots) {
                    foreach (string folder in CANDIDATE_FOLDERS) {
                        var dir = root.resolve_relative_path (Path.build_filename (phone_root.substring (1), folder));
                        yield scan_folder (dir, candidates);
                    }
                }
                candidates.sort ((a, b) => (int) (b.mtime_ms - a.mtime_ms).clamp (-1, 1));

                var dir = cache_dir (id);
                if (!dir.query_exists ()) {
                    dir.make_directory_with_parents ();
                }
                var kept = new GenericSet<string> (str_hash, str_equal);
                var list = new GenericArray<Core.HistoryItem> ();
                for (uint i = 0; i < candidates.length && i < MAX_IMAGES; i++) {
                    var c = candidates[i];
                    string local_name = "%s-%s".printf (c.mtime_ms.to_string (), c.name);
                    var target = dir.get_child (local_name);
                    kept.add (local_name);
                    if (!target.query_exists ()) {
                        try {
                            yield c.file.copy_async (target, FileCopyFlags.OVERWRITE, Priority.DEFAULT, null, null);
                            var fi = new FileInfo ();
                            fi.set_attribute_uint64 (FileAttribute.TIME_MODIFIED, (uint64) (c.mtime_ms / 1000));
                            yield target.set_attributes_async (fi, FileQueryInfoFlags.NONE, Priority.DEFAULT, null, null);
                        } catch (Error e) {
                            warning ("Cannot fetch %s from %s: %s", c.name, device.name, e.message);
                            continue;
                        }
                    }
                    var item = new Core.HistoryItem (Core.HistoryKind.FILE, target.get_path (), true);
                    item.time_ms = c.mtime_ms;
                    list.add (item);
                }
                /* Drop cached files that fell out of the newest set. */
                try {
                    var it = yield dir.enumerate_children_async ("standard::name", FileQueryInfoFlags.NONE);
                    FileInfo? fi;
                    while ((fi = it.next_file ()) != null) {
                        if (!(fi.get_name () in kept)) {
                            dir.get_child (fi.get_name ()).delete ();
                        }
                    }
                } catch (Error e) {
                    debug ("gallery prune: %s", e.message);
                }
                items.insert (id, list);
                GLib.info ("Gallery for %s: %u images", device.name, list.length);
                updated (id);
            } catch (Error e) {
                warning ("Gallery fetch from %s failed: %s", device.name, e.message);
                failed (id, e.message);
            } finally {
                busy.remove (id);
                busy_changed (id, false);
                if (mount != null) {
                    mount.unmount_with_operation.begin (MountUnmountFlags.NONE, null, null, (o, r) => {
                        try {
                            mount.unmount_with_operation.end (r);
                        } catch (Error e) {
                            debug ("unmount: %s", e.message);
                        }
                    });
                }
            }
        }

        private async void scan_folder (File dir, GenericArray<Candidate> into) {
            FileEnumerator it;
            try {
                it = yield dir.enumerate_children_async (
                    "standard::name,standard::type,standard::content-type,standard::size,time::modified",
                    FileQueryInfoFlags.NONE);
            } catch (Error e) {
                debug ("skip %s: %s", dir.get_uri (), e.message);
                return;
            }
            uint seen = 0;
            try {
                while (true) {
                    var batch = yield it.next_files_async (50);
                    if (batch == null || batch.length () == 0) {
                        break;
                    }
                    foreach (var fi in batch) {
                        if (fi.get_file_type () != FileType.REGULAR) {
                            continue;
                        }
                        bool uncertain;
                        string? ct = fi.get_content_type () ?? ContentType.guess (fi.get_name (), null, out uncertain);
                        if (ct == null || !ct.has_prefix ("image/")) {
                            continue;
                        }
                        var c = new Candidate ();
                        c.file = dir.get_child (fi.get_name ());
                        c.name = fi.get_name ();
                        c.size = fi.get_size ();
                        var dt = fi.get_modification_date_time ();
                        c.mtime_ms = dt != null ? dt.to_unix () * 1000 : 0;
                        into.add (c);
                        seen++;
                    }
                    if (seen >= IMAGE_LIMIT_PER_FOLDER * 10) {
                        break;
                    }
                }
            } catch (Error e) {
                debug ("listing %s: %s", dir.get_uri (), e.message);
            }
        }
    }
}
