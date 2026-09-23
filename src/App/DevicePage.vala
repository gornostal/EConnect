/*
 * SPDX-License-Identifier: MIT
 *
 * Right-hand pane for one device: status, a composer for sending things,
 * running transfers, recent images and the Activity log.
 */
namespace EConnect.App {

    public class DevicePage : Gtk.Box {
        public Core.Device device { get; construct; }
        public Application app { get; construct; }

        public signal void toast (string message);
        /** A short "Sending · 40 %" summary for the sidebar, or null when idle. */
        public signal void busy_changed (string? text);

        private DeviceAvatar avatar;
        private Gtk.Label pill;
        private Gtk.Label status_detail;
        private Gtk.Button pair_button;
        private Gtk.MenuButton menu_button;
        private SimpleAction ping_action;
        private SimpleAction unpair_action;

        private Gtk.Box composer;
        private Gtk.Box lock_bar;
        private Gtk.Image lock_icon;
        private Gtk.Spinner lock_spinner;
        private Gtk.Label lock_label;
        private Gtk.Box composer_body;
        private Gtk.Entry text_entry;
        private Gtk.Box clip_line;
        private Gtk.Label clip_label;
        private Gtk.Label clip_text;
        private Gtk.Box transfers;
        private Gtk.Box transfer_rows;
        private Gtk.Label transfers_title;
        private Gtk.DropTarget drop_target;

        private Gtk.Widget images_section;
        private Gtk.Grid images_grid;
        private Gtk.Label images_empty;
        private Gtk.Spinner images_spinner;
        private Gtk.Button images_refresh;

        private Gtk.Widget activity_section;
        private Gtk.CustomFilter activity_filter;
        private Core.HistoryKind? filter_kind = null;
        private Gtk.Button clear_button;

        private HashTable<string, TransferRow> incoming = new HashTable<string, TransferRow> (str_hash, str_equal);

        public DevicePage (Application app, Core.Device device) {
            Object (app: app, device: device, orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        }

        construct {
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 30) {
                margin_top = 8, margin_bottom = 48, margin_start = 32, margin_end = 32
            };
            images_section = build_images ();
            activity_section = build_activity ();
            content.append (build_header ());
            content.append (build_composer ());
            content.append (images_section);
            content.append (activity_section);

            var scroll = new Gtk.ScrolledWindow () {
                child = new Clamp (740) { child = content },
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vexpand = true
            };
            append (scroll);

            /* Drop files anywhere on the page to send them. */
            drop_target = new Gtk.DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
            drop_target.drop.connect ((value, x, y) => {
                /* Ignore our own thumbnails and Activity rows being dragged around. */
                var current = drop_target.get_current_drop ();
                if (current != null && current.get_drag () != null) {
                    return false;
                }
                foreach (var file in ((Gdk.FileList) value.get_boxed ()).get_files ()) {
                    send_file (file);
                }
                return true;
            });
            add_controller (drop_target);

            connect_signals ();
            refresh ();
            refresh_images ();
        }

        /* ---- header ---- */

        private Gtk.Widget build_header () {
            avatar = new DeviceAvatar (device.device_type, true);
            var name = new Gtk.Label (device.name) {
                halign = Gtk.Align.START,
                ellipsize = Pango.EllipsizeMode.END
            };
            name.add_css_class ("device-title");
            pill = new Gtk.Label ("") { valign = Gtk.Align.CENTER };
            pill.add_css_class ("pill");
            status_detail = new Gtk.Label ("") { ellipsize = Pango.EllipsizeMode.END };
            status_detail.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            var status_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { margin_top = 4 };
            status_row.append (pill);
            status_row.append (status_detail);
            var title_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { valign = Gtk.Align.CENTER, hexpand = true };
            title_box.append (name);
            title_box.append (status_row);

            pair_button = new Gtk.Button.with_label (_("Pair")) { valign = Gtk.Align.CENTER };
            pair_button.add_css_class (Granite.STYLE_CLASS_SUGGESTED_ACTION);
            pair_button.clicked.connect (on_pair_clicked);

            var actions = new SimpleActionGroup ();
            ping_action = new SimpleAction ("ping", null);
            ping_action.activate.connect (() => {
                if (app.ping.send_ping (device)) {
                    toast (_("Ping sent to %s").printf (device.name));
                }
            });
            actions.add_action (ping_action);
            unpair_action = new SimpleAction ("unpair", null);
            unpair_action.activate.connect (confirm_unpair);
            actions.add_action (unpair_action);
            insert_action_group ("device", actions);

            var menu = new Menu ();
            menu.append (_("Ping"), "device.ping");
            var danger = new Menu ();
            danger.append (_("Unpair…"), "device.unpair");
            menu.append_section (null, danger);
            menu_button = new Gtk.MenuButton () {
                icon_name = "view-more-symbolic",
                menu_model = menu,
                tooltip_text = _("More"),
                valign = Gtk.Align.CENTER
            };
            menu_button.add_css_class (Granite.STYLE_CLASS_FLAT);

            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 16);
            header.append (avatar);
            header.append (title_box);
            header.append (pair_button);
            header.append (menu_button);
            return header;
        }

        /* ---- composer, clipboard line and transfers ---- */

        private Gtk.Widget build_composer () {
            lock_icon = new Gtk.Image () { valign = Gtk.Align.CENTER };
            lock_spinner = new Gtk.Spinner () { valign = Gtk.Align.CENTER };
            lock_label = new Gtk.Label ("") { wrap = true, xalign = 0, hexpand = true };
            lock_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            lock_bar.add_css_class ("lock");
            lock_bar.append (lock_icon);
            lock_bar.append (lock_spinner);
            lock_bar.append (lock_label);

            text_entry = new Gtk.Entry () {
                placeholder_text = _("Type or paste text or a link"),
                hexpand = true
            };
            text_entry.add_css_class ("composer-entry");
            text_entry.activate.connect (on_send_text);
            text_entry.changed.connect (() => {
                bool url = looks_like_url (text_entry.text.strip ());
                text_entry.secondary_icon_name = url ? "insert-link-symbolic" : null;
                text_entry.secondary_icon_tooltip_text = url ? _("Will be sent as a link") : null;
            });
            /* Fills the row so it matches the taller text field. */
            var send_text = new Gtk.Button.with_label (_("Send"));
            send_text.add_css_class (Granite.STYLE_CLASS_SUGGESTED_ACTION);
            send_text.add_css_class ("composer-send");
            send_text.clicked.connect (on_send_text);
            text_entry.bind_property ("text", send_text, "sensitive", BindingFlags.SYNC_CREATE,
                                      (b, from, ref to) => { to = from.get_string ().strip () != ""; return true; });
            var text_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            text_row.append (text_entry);
            text_row.append (send_text);

            var send_files = new Gtk.Button () { child = button_content ("mail-attachment-symbolic", _("Send Files…")) };
            send_files.clicked.connect (on_send_files);
            var send_shot = new Gtk.Button () {
                child = button_content ("camera-photo-symbolic", _("Send Screenshot")),
                tooltip_text = _("Take a screenshot and send it")
            };
            send_shot.clicked.connect (on_send_screenshot);
            var drop_hint = new Gtk.Label (_("or drop files anywhere")) { hexpand = true, xalign = 1 };
            drop_hint.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            drop_hint.add_css_class (Granite.STYLE_CLASS_SMALL_LABEL);
            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            buttons.append (send_files);
            buttons.append (send_shot);
            buttons.append (drop_hint);

            composer_body = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            composer_body.add_css_class ("composer-body");
            composer_body.append (text_row);
            composer_body.append (buttons);

            composer = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            composer.add_css_class ("composer");
            composer.append (lock_bar);
            composer.append (composer_body);

            clip_label = new Gtk.Label ("");
            clip_label.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            clip_text = new Gtk.Label ("") { xalign = 0, hexpand = true, ellipsize = Pango.EllipsizeMode.END };
            clip_line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { visible = false, margin_start = 4 };
            clip_line.add_css_class ("clip-line");
            clip_line.add_css_class (Granite.STYLE_CLASS_SMALL_LABEL);
            clip_line.append (new Gtk.Image.from_icon_name ("edit-paste-symbolic"));
            clip_line.append (clip_label);
            clip_line.append (clip_text);

            transfers_title = new Gtk.Label ("") { xalign = 0 };
            transfers_title.add_css_class ("day-label");
            transfer_rows = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            transfers = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) { visible = false };
            transfers.add_css_class ("transfers");
            transfers.append (transfers_title);
            transfers.append (transfer_rows);

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            box.append (composer);
            box.append (clip_line);
            box.append (transfers);
            return box;
        }

        /* ---- recent images ---- */

        private Gtk.Widget build_images () {
            var title = new Gtk.Label (_("Recent Images")) { xalign = 0 };
            title.add_css_class ("section-title");
            var sub = new Gtk.Label (Plugins.Sftp.supported_by (device)
                ? _("Newest photos and screenshots") : _("Shared with this computer")) {
                xalign = 0,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END
            };
            sub.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            sub.add_css_class (Granite.STYLE_CLASS_SMALL_LABEL);
            images_spinner = new Gtk.Spinner ();
            images_refresh = new Gtk.Button.from_icon_name ("view-refresh-symbolic") {
                tooltip_text = _("Fetch the newest photos and screenshots from the phone"),
                valign = Gtk.Align.CENTER
            };
            images_refresh.add_css_class (Granite.STYLE_CLASS_FLAT);
            images_refresh.clicked.connect (() => {
                if (!app.gallery.refresh (device)) {
                    toast (_("%s is not reachable").printf (device.name));
                }
            });
            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            header.append (title);
            header.append (sub);
            header.append (images_spinner);
            header.append (images_refresh);

            images_grid = new Gtk.Grid () { column_homogeneous = true, column_spacing = 10 };
            images_empty = new Gtk.Label (Plugins.Sftp.supported_by (device)
                ? _("The newest photos and screenshots on %s will show up here.").printf (device.name)
                : _("Images shared from %s will show up here.").printf (device.name)) {
                wrap = true
            };
            images_empty.add_css_class ("empty-note");

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            box.append (header);
            box.append (images_grid);
            box.append (images_empty);
            return box;
        }

        /* ---- activity ---- */

        private Gtk.Widget build_activity () {
            var title = new Gtk.Label (_("Activity")) { xalign = 0, hexpand = true };
            title.add_css_class ("section-title");

            var filters = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2) { valign = Gtk.Align.CENTER };
            filters.add_css_class ("segmented");
            Gtk.ToggleButton? first = null;
            add_filter (filters, ref first, _("All"), null);
            add_filter (filters, ref first, _("Files"), Core.HistoryKind.FILE);
            add_filter (filters, ref first, _("Links"), Core.HistoryKind.URL);
            add_filter (filters, ref first, _("Text"), Core.HistoryKind.TEXT);

            var downloads = new Gtk.Button.from_icon_name ("folder-download-symbolic") {
                tooltip_text = _("Open the Downloads folder"),
                valign = Gtk.Align.CENTER
            };
            downloads.add_css_class (Granite.STYLE_CLASS_FLAT);
            downloads.clicked.connect (() => launch (app.share.download_dir.get_uri (), _("Downloads")));
            clear_button = new Gtk.Button.from_icon_name ("edit-clear-all-symbolic") {
                tooltip_text = _("Clear Activity"),
                valign = Gtk.Align.CENTER
            };
            clear_button.add_css_class (Granite.STYLE_CLASS_FLAT);
            clear_button.clicked.connect (clear_activity);

            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            header.append (title);
            header.append (filters);
            header.append (downloads);
            header.append (clear_button);

            var store = app.history.for_device (device.id);
            activity_filter = new Gtk.CustomFilter ((obj) => {
                return filter_kind == null || ((Core.HistoryItem) obj).kind == filter_kind;
            });
            var filtered = new Gtk.FilterListModel (store, activity_filter);

            var empty = new Gtk.Label (_("Things you send to and receive from %s will be listed here.").printf (device.name)) {
                wrap = true
            };
            empty.add_css_class ("empty-note");

            var list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE };
            list.add_css_class ("activity");
            list.set_placeholder (empty);
            list.bind_model (filtered, (obj) => {
                var row = new ActivityRow ((Core.HistoryItem) obj);
                row.open.connect (open_item);
                row.copy.connect (copy_item);
                row.show_in_folder.connect (show_item);
                row.remove.connect (remove_item);
                return row;
            });
            list.set_header_func ((row, before) => {
                var item = ((ActivityRow) row).item;
                if (before != null && Util.same_day (item.time_ms, ((ActivityRow) before).item.time_ms)) {
                    row.set_header (null);
                    return;
                }
                var label = new Gtk.Label (Util.day_label (item.time_ms).up ()) { xalign = 0 };
                label.add_css_class ("day-label");
                row.set_header (label);
            });
            list.row_activated.connect ((row) => open_item (((ActivityRow) row).item));
            store.items_changed.connect (() => clear_button.sensitive = store.get_n_items () > 0);
            clear_button.sensitive = store.get_n_items () > 0;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            box.append (header);
            box.append (list);
            return box;
        }

        private void add_filter (Gtk.Box box, ref Gtk.ToggleButton? first, string label, Core.HistoryKind? kind) {
            var button = new Gtk.ToggleButton.with_label (label) { active = first == null };
            if (first != null) {
                button.group = first;
            } else {
                first = button;
            }
            button.toggled.connect (() => {
                if (button.active) {
                    filter_kind = kind;
                    activity_filter.changed (Gtk.FilterChange.DIFFERENT);
                }
            });
            box.append (button);
        }

        private Gtk.Widget button_content (string icon_name, string label) {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            box.append (new Gtk.Image.from_icon_name (icon_name));
            box.append (new Gtk.Label (label));
            return box;
        }

        private void connect_signals () {
            app.history.item_added.connect ((id, item) => {
                if (id == device.id) {
                    refresh_images ();
                }
            });
            app.gallery.updated.connect ((id) => {
                if (id == device.id) {
                    refresh_images ();
                }
            });
            app.gallery.failed.connect ((id, reason) => {
                if (id == device.id) {
                    string hint = reason.down ().contains ("permission")
                        ? _("On the phone, open KDE Connect, choose this computer, then Plugin settings → Filesystem expose and allow storage access.")
                        : reason;
                    toast (_("Could not read photos from %s: %s").printf (device.name, hint));
                }
            });
            app.gallery.busy_changed.connect ((id, is_busy) => {
                if (id == device.id) {
                    images_spinner.spinning = is_busy;
                    images_refresh.sensitive = !is_busy;
                }
            });
            app.clipboard.clipboard_received.connect ((d, text) => {
                if (d == device) {
                    var now = new GLib.DateTime.now_local ();
                    clip_label.label = _("Clipboard synced from %s at %s ·").printf (
                        device.name, now.format (Util.time_format ()));
                    clip_text.label = "“%s”".printf (text.replace ("\n", " "));
                    clip_line.visible = true;
                }
            });

            app.share.file_started.connect ((d, fname, size) => {
                if (d == device) {
                    var row = new TransferRow (fname, true, null);
                    row.set_progress (0, size);
                    incoming.insert (fname, row);
                    add_transfer (row);
                }
            });
            app.share.file_progress.connect ((d, fname, done, size) => {
                if (d == device) {
                    var row = incoming.lookup (fname);
                    if (row != null && row.set_progress (done, size)) {
                        update_busy ();
                    }
                }
            });
            app.share.file_received.connect ((d, f) => {
                if (d == device) {
                    finish_incoming (f.get_basename ());
                }
            });
            app.share.file_failed.connect ((d, fname, why) => {
                if (d == device) {
                    finish_incoming (fname);
                    toast (_("Could not receive %s: %s").printf (fname, why));
                }
            });

            device.reachable_changed.connect (refresh);
            device.paired_changed.connect (refresh);
            device.pairing.notify["state"].connect (refresh);
            device.pairing_failed.connect ((reason) => toast (_("Pairing failed: %s").printf (reason)));
        }

        /* ---- state ---- */

        private bool usable {
            get { return device.is_paired && device.is_reachable; }
        }

        private void refresh () {
            string state = Util.device_state (device);
            bool paired = device.is_paired;
            bool reachable = device.is_reachable;
            bool incoming_request = device.pair_state == Core.PairState.REQUESTED_BY_PEER;

            avatar.set_state (state);
            foreach (unowned string s in new string[] { "connected", "available", "pairing", "offline" }) {
                pill.remove_css_class (s);
            }
            pill.add_css_class (state);
            lock_bar.remove_css_class ("warn");
            lock_spinner.spinning = false;
            lock_spinner.visible = false;
            lock_icon.visible = true;
            switch (state) {
                case "connected":
                    pill.label = _("Connected");
                    status_detail.label = "";
                    break;
                case "pairing":
                    pill.label = incoming_request ? _("Wants to pair") : _("Pairing…");
                    status_detail.label = _("Compare the code on both screens");
                    lock_bar.add_css_class ("warn");
                    lock_icon.visible = false;
                    lock_spinner.visible = true;
                    lock_spinner.spinning = true;
                    lock_label.label = incoming_request
                        ? _("%s wants to pair. Accept only if it shows the same code.").printf (device.name)
                        : _("Waiting for %s to accept…").printf (device.name);
                    break;
                case "offline":
                    pill.label = _("Offline");
                    status_detail.label = paired ? _("Paired") : "";
                    lock_icon.icon_name = "network-offline-symbolic";
                    lock_label.label = _("%s is offline. Open KDE Connect on it and join the same Wi-Fi network as this computer.").printf (device.name);
                    break;
                default:
                    pill.label = _("Not paired");
                    status_detail.label = _("Available on this network");
                    lock_icon.icon_name = "changes-prevent-symbolic";
                    lock_label.label = _("Pair with %s to send files, links and text. You will compare a code on both screens.").printf (device.name);
                    break;
            }

            lock_bar.visible = !usable;
            composer_body.sensitive = usable;
            if (usable) {
                composer.remove_css_class ("locked");
            } else {
                composer.add_css_class ("locked");
            }
            pair_button.visible = reachable && !paired;
            pair_button.sensitive = device.pair_state == Core.PairState.NOT_PAIRED || incoming_request;
            ping_action.set_enabled (usable);
            unpair_action.set_enabled (paired);
            menu_button.visible = paired;
            /* Until the device is paired there is nothing to show. */
            images_section.visible = paired;
            activity_section.visible = paired;
            drop_target.actions = usable ? Gdk.DragAction.COPY : 0;
            images_refresh.visible = Plugins.Sftp.supported_by (device);
            images_refresh.sensitive = usable && !app.gallery.is_busy (device.id);
        }

        private void refresh_images () {
            Gtk.Widget? child;
            while ((child = images_grid.get_first_child ()) != null) {
                images_grid.remove (child);
            }
            /* Merge what the phone's gallery gave us with images it shared to us. */
            var merged = new GenericArray<Core.HistoryItem> ();
            foreach (var item in app.gallery.get_items (device.id)) {
                if (item.file_exists) {
                    merged.add (item);
                }
            }
            foreach (var item in app.history.recent_images (device.id, Gallery.MAX_IMAGES)) {
                if (item.incoming) {
                    merged.add (item);
                }
            }
            merged.sort ((a, b) => (int) (b.time_ms - a.time_ms).clamp (-1, 1));
            int shown = 0;
            for (uint i = 0; i < merged.length && shown < Gallery.MAX_IMAGES; i++) {
                images_grid.attach (thumbnail (merged[i]), shown, 0);
                shown++;
            }
            /* Keep the columns the same width when there are fewer images. */
            for (int col = shown; shown > 0 && col < Gallery.MAX_IMAGES; col++) {
                images_grid.attach (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0), col, 0);
            }
            images_grid.visible = shown > 0;
            images_empty.visible = shown == 0;
        }

        private Gtk.Widget thumbnail (Core.HistoryItem item) {
            var picture = new Thumbnail (item.value, 120);
            var button = new Gtk.Button () {
                child = picture,
                tooltip_text = Path.get_basename (item.value),
                overflow = Gtk.Overflow.HIDDEN,
                valign = Gtk.Align.START
            };
            button.add_css_class ("thumb");
            button.clicked.connect (() => open_item (item));
            Util.make_draggable (button, item.value, picture);
            return button;
        }

        /* ---- transfers ---- */

        private void add_transfer (TransferRow row) {
            transfer_rows.append (row);
            transfers.visible = true;
            update_busy ();
        }

        private void remove_transfer (TransferRow row) {
            transfer_rows.remove (row);
            transfers.visible = transfer_rows.get_first_child () != null;
            update_busy ();
        }

        private void finish_incoming (string fname) {
            var row = incoming.lookup (fname);
            if (row != null) {
                incoming.remove (fname);
                remove_transfer (row);
            }
        }

        private void update_busy () {
            var first = transfer_rows.get_first_child () as TransferRow;
            if (first == null) {
                busy_changed (null);
                return;
            }
            int count = 0;
            for (var c = transfer_rows.get_first_child (); c != null; c = c.get_next_sibling ()) {
                count++;
            }
            transfers_title.label = ngettext ("%d transfer", "%d transfers", count).printf (count).up ();
            int percent = int.max (first.percent, 0);
            busy_changed ((first.incoming ? _("Receiving · %d %%") : _("Sending · %d %%")).printf (percent));
        }

        /* ---- actions ---- */

        private void on_pair_clicked () {
            bool incoming_request = device.pair_state == Core.PairState.REQUESTED_BY_PEER;
            if (!incoming_request && !device.request_pairing ()) {
                return;
            }
            var dialog = new PairDialog (get_root () as Gtk.Window, device, incoming_request);
            dialog.present ();
        }

        public void show_incoming_pair_request () {
            var dialog = new PairDialog (get_root () as Gtk.Window, device, true);
            dialog.present ();
        }

        private void confirm_unpair () {
            var dialog = new Granite.MessageDialog.with_image_from_icon_name (
                _("Unpair %s?").printf (device.name),
                _("It will no longer be able to send you files or sync the clipboard. You can pair again at any time. Activity on this computer is kept."),
                device.device_type.icon_name (),
                Gtk.ButtonsType.CANCEL) {
                transient_for = get_root () as Gtk.Window,
                modal = true
            };
            var unpair = dialog.add_button (_("Unpair"), Gtk.ResponseType.ACCEPT);
            unpair.add_css_class (Granite.STYLE_CLASS_DESTRUCTIVE_ACTION);
            dialog.response.connect ((id) => {
                if (id == Gtk.ResponseType.ACCEPT) {
                    device.unpair ();
                }
                dialog.destroy ();
            });
            dialog.present ();
        }

        private static bool looks_like_url (string text) {
            try {
                return (text.has_prefix ("http://") || text.has_prefix ("https://"))
                       && Uri.is_valid (text, UriFlags.NONE);
            } catch (Error e) {
                return false;
            }
        }

        private void on_send_text () {
            string text = text_entry.text.strip ();
            if (text == "") {
                return;
            }
            bool url = looks_like_url (text);
            bool ok = url ? app.share.send_url (device, text) : app.share.send_text (device, text);
            if (ok) {
                text_entry.text = "";
                app.history.add (device.id, new Core.HistoryItem (
                    url ? Core.HistoryKind.URL : Core.HistoryKind.TEXT, text, false));
                toast (_("Sent to %s").printf (device.name));
            } else {
                toast (_("%s is not reachable").printf (device.name));
            }
        }

        private void on_send_files () {
            var dialog = new Gtk.FileDialog () { title = _("Send Files to %s").printf (device.name) };
            dialog.open_multiple.begin (get_root () as Gtk.Window, null, (obj, res) => {
                ListModel files;
                try {
                    files = dialog.open_multiple.end (res);
                } catch (Error e) {
                    return;   // cancelled
                }
                for (uint i = 0; i < files.get_n_items (); i++) {
                    send_file ((File) files.get_item (i));
                }
            });
        }

        private void on_send_screenshot () {
            Screenshot.take.begin (get_root () as Gtk.Window, true, (obj, res) => {
                try {
                    send_file (Screenshot.take.end (res));
                } catch (Error e) {
                    if (!(e is IOError.CANCELLED)) {
                        toast (e.message);
                    }
                }
            });
        }

        private void send_file (File file) {
            var cancel = new Cancellable ();
            var row = new TransferRow (file.get_basename (), false, cancel);
            add_transfer (row);
            app.share.send_file.begin (device, file, cancel, (done, total) => {
                if (row.set_progress (done, total)) {
                    update_busy ();
                }
            }, (obj, res) => {
                remove_transfer (row);
                var item = new Core.HistoryItem (Core.HistoryKind.FILE, file.get_path (), false);
                try {
                    app.share.send_file.end (res);
                    toast (_("Sent %s").printf (file.get_basename ()));
                } catch (Error e) {
                    if (e is IOError.CANCELLED) {
                        return;
                    }
                    item.error = e.message;
                    toast (_("Could not send %s: %s").printf (file.get_basename (), e.message));
                }
                app.history.add (device.id, item);
            });
        }

        /* ---- activity actions ---- */

        private void launch (string uri, string what) {
            Util.open_uri.begin (uri, get_root () as Gtk.Window, (o, res) => {
                try {
                    Util.open_uri.end (res);
                } catch (Error e) {
                    toast (_("Could not open %s: %s").printf (what, e.message));
                }
            });
        }

        private void open_item (Core.HistoryItem item) {
            if (item.kind == Core.HistoryKind.TEXT) {
                copy_item (item);
                return;
            }
            if (item.kind == Core.HistoryKind.FILE && !item.file_exists) {
                toast (_("%s was moved or deleted").printf (Path.get_basename (item.value)));
                return;
            }
            if (item.kind == Core.HistoryKind.FILE) {
                launch (File.new_for_path (item.value).get_uri (), Path.get_basename (item.value));
            } else {
                launch (item.value, item.value);
            }
        }

        private void copy_item (Core.HistoryItem item) {
            get_clipboard ().set_text (item.value);
            toast (_("Copied to clipboard"));
        }

        private void show_item (Core.HistoryItem item) {
            Util.show_in_folder.begin (File.new_for_path (item.value), get_root () as Gtk.Window, (o, res) => {
                try {
                    Util.show_in_folder.end (res);
                } catch (Error e) {
                    toast (_("Could not show %s: %s").printf (Path.get_basename (item.value), e.message));
                }
            });
        }

        private void remove_item (Core.HistoryItem item) {
            app.history.remove (device.id, item);
            var window = get_root () as MainWindow;
            if (window != null) {
                window.show_undo_toast (_("Removed from Activity"), () => {
                    app.history.restore (device.id, { item });
                });
            }
        }

        private void clear_activity () {
            var removed = app.history.clear (device.id);
            refresh_images ();
            var window = get_root () as MainWindow;
            if (window != null) {
                window.show_undo_toast (_("Activity cleared"), () => {
                    app.history.restore (device.id, removed);
                    refresh_images ();
                });
            }
        }
    }

    /** One file on its way in or out, with a progress bar. */
    private class TransferRow : Gtk.Box {
        public bool incoming { get; construct; }
        public int percent { get; private set; default = -1; }

        private Gtk.Label size_label;
        private Gtk.ProgressBar bar;

        public TransferRow (string filename, bool incoming, Cancellable? cancel) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 12, incoming: incoming);

            var icon = new Gtk.Image.from_icon_name (incoming ? "go-down-symbolic" : "go-up-symbolic") { hexpand = true };
            var tile = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { valign = Gtk.Align.CENTER };
            tile.add_css_class ("transfer-icon");
            if (!incoming) {
                tile.add_css_class ("out");
            }
            tile.append (icon);
            /* Set explicitly so the expanding icon does not stretch the tile. */
            tile.hexpand = tile.vexpand = false;
            var name = new Gtk.Label (filename) {
                xalign = 0,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.MIDDLE,
                tooltip_text = incoming ? _("Receiving %s").printf (filename) : _("Sending %s").printf (filename)
            };
            size_label = new Gtk.Label ("");
            size_label.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            size_label.add_css_class (Granite.STYLE_CLASS_SMALL_LABEL);
            var top = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            top.append (name);
            top.append (size_label);
            bar = new Gtk.ProgressBar ();
            bar.add_css_class ("thin");
            if (!incoming) {
                bar.add_css_class ("out");
            }
            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 5) { valign = Gtk.Align.CENTER, hexpand = true };
            text.append (top);
            text.append (bar);

            append (tile);
            append (text);
            if (cancel != null) {
                var stop = new Gtk.Button.from_icon_name ("process-stop-symbolic") {
                    tooltip_text = _("Cancel"),
                    valign = Gtk.Align.CENTER
                };
                stop.add_css_class (Granite.STYLE_CLASS_FLAT);
                stop.clicked.connect (() => cancel.cancel ());
                append (stop);
            }
        }

        /** Returns true when the whole-number percentage changed. */
        public bool set_progress (int64 done, int64 total) {
            if (total <= 0) {
                bar.pulse ();
                size_label.label = format_size (done);
                return false;
            }
            int p = (int) (done * 100 / total);
            if (p == percent) {
                return false;
            }
            percent = p;
            bar.fraction = (double) done / (double) total;
            /* Translators: transferred and total size, e.g. "1.2 MB of 3.4 MB" */
            size_label.label = _("%s of %s").printf (format_size (done), format_size (total));
            return true;
        }
    }

    private class ActivityRow : Gtk.ListBoxRow {
        public Core.HistoryItem item { get; construct; }

        public signal void open (Core.HistoryItem item);
        public signal void copy (Core.HistoryItem item);
        public signal void show_in_folder (Core.HistoryItem item);
        public signal void remove (Core.HistoryItem item);

        private Gtk.MenuButton menu_button;

        public ActivityRow (Core.HistoryItem item) {
            Object (item: item);
        }

        construct {
            add_css_class ("activity-row");
            bool is_file = item.kind == Core.HistoryKind.FILE;
            bool exists = item.file_exists;
            string text = is_file ? Path.get_basename (item.value) : item.value.replace ("\n", " ");

            var tile = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                valign = Gtk.Align.CENTER,
                overflow = Gtk.Overflow.HIDDEN
            };
            tile.add_css_class ("item-icon");
            if (item.is_image && exists) {
                tile.append (new Thumbnail (item.value, 38));
            } else {
                GLib.Icon gicon;
                if (item.failed) {
                    gicon = new ThemedIcon ("dialog-error-symbolic");
                    tile.add_css_class ("failed");
                } else if (item.kind == Core.HistoryKind.URL) {
                    gicon = new ThemedIcon ("insert-link-symbolic");
                } else if (item.kind == Core.HistoryKind.TEXT) {
                    gicon = new ThemedIcon ("text-x-generic-symbolic");
                } else {
                    bool uncertain;
                    gicon = ContentType.get_symbolic_icon (ContentType.guess (item.value, null, out uncertain));
                }
                tile.append (new Gtk.Image.from_gicon (gicon) { hexpand = true, vexpand = true });
            }
            tile.hexpand = tile.vexpand = false;

            var title = new Gtk.Label (text) {
                xalign = 0,
                ellipsize = Pango.EllipsizeMode.END,
                width_chars = 10,
                max_width_chars = 60
            };
            if (item.failed) {
                title.add_css_class ("failed-title");
            } else if (item.kind == Core.HistoryKind.URL) {
                title.add_css_class ("link");
            }

            var dir_icon = new Gtk.Image.from_icon_name (item.incoming ? "go-down-symbolic" : "go-up-symbolic") {
                pixel_size = 12
            };
            var dir_label = new Gtk.Label (item.incoming ? _("Received") : _("Sent"));
            var dir_tag = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3);
            dir_tag.add_css_class ("dir-tag");
            dir_tag.add_css_class (item.incoming ? "in" : "out");
            dir_tag.append (dir_icon);
            dir_tag.append (dir_label);

            string? detail = null;
            if (item.failed) {
                detail = _("Failed: %s").printf (item.error);
            } else if (is_file && !exists) {
                detail = _("Moved or deleted");
            } else if (is_file) {
                try {
                    var info = File.new_for_path (item.value).query_info (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
                    detail = format_size (info.get_size ());
                } catch (Error e) {
                    detail = null;
                }
            }
            var meta = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            meta.add_css_class (Granite.STYLE_CLASS_SMALL_LABEL);
            meta.append (dir_tag);
            if (detail != null) {
                var detail_label = new Gtk.Label ("· " + detail) { ellipsize = Pango.EllipsizeMode.END };
                detail_label.add_css_class (item.failed ? "error-text" : Granite.STYLE_CLASS_DIM_LABEL);
                meta.append (detail_label);
            }

            var labels = new Gtk.Box (Gtk.Orientation.VERTICAL, 1) { hexpand = true, valign = Gtk.Align.CENTER };
            labels.append (title);
            labels.append (meta);

            var when = new GLib.DateTime.from_unix_local (item.time_ms / 1000);
            var time_label = new Gtk.Label (when.format (Util.time_format ()));
            time_label.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            time_label.add_css_class (Granite.STYLE_CLASS_SMALL_LABEL);

            var actions = new SimpleActionGroup ();
            add_row_action (actions, "open", () => open (item), (is_file && exists) || item.kind == Core.HistoryKind.URL);
            add_row_action (actions, "copy", () => copy (item), !is_file);
            add_row_action (actions, "show", () => show_in_folder (item), is_file && exists);
            add_row_action (actions, "remove", () => remove (item), true);
            insert_action_group ("row", actions);

            var menu = new Menu ();
            if (is_file || item.kind == Core.HistoryKind.URL) {
                menu.append (_("Open"), "row.open");
            }
            if (is_file) {
                menu.append (_("Show in Folder"), "row.show");
            } else {
                menu.append (_("Copy"), "row.copy");
            }
            var remove_section = new Menu ();
            remove_section.append (_("Remove from Activity"), "row.remove");
            menu.append_section (null, remove_section);
            menu_button = new Gtk.MenuButton () {
                icon_name = "view-more-symbolic",
                menu_model = menu,
                tooltip_text = _("More"),
                valign = Gtk.Align.CENTER
            };
            menu_button.add_css_class (Granite.STYLE_CLASS_FLAT);
            menu_button.add_css_class ("row-menu");

            /* The menu button only shows on hover, so offer the same menu on
             * right click and long press. */
            var right_click = new Gtk.GestureClick () { button = Gdk.BUTTON_SECONDARY };
            right_click.pressed.connect (() => menu_button.popup ());
            add_controller (right_click);
            var long_press = new Gtk.GestureLongPress () { touch_only = true };
            long_press.pressed.connect (() => menu_button.popup ());
            add_controller (long_press);

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            box.append (tile);
            box.append (labels);
            box.append (time_label);
            box.append (menu_button);
            child = box;
            activatable = !item.failed && !(is_file && !exists);
            tooltip_text = item.kind == Core.HistoryKind.TEXT ? _("Copy to clipboard") : null;
            if (is_file && exists) {
                Util.make_draggable (this, item.value, null);
            }
        }

        private void add_row_action (SimpleActionGroup group, string name, owned ActionFunc func, bool enabled) {
            var action = new SimpleAction (name, null);
            action.activate.connect (() => func ());
            action.set_enabled (enabled);
            group.add_action (action);
        }

        private delegate void ActionFunc ();
    }
}
