/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Right-hand pane for one device: status, actions, recent images and items.
 */
namespace EConnect.App {

    public class DevicePage : Gtk.Box {
        public Core.Device device { get; construct; }
        public Application app { get; construct; }

        public signal void toast (string message);

        private Gtk.Label status_label;
        private Gtk.Button pair_button;
        private Gtk.Button unpair_button;
        private Gtk.Box actions;
        private Gtk.Box images_box;
        private Gtk.Label images_empty;
        private Gtk.ListBox items_list;
        private Gtk.Entry text_entry;
        private Gtk.ProgressBar progress;
        private Gtk.Spinner images_spinner;
        private Gtk.Button images_refresh;

        public DevicePage (Application app, Core.Device device) {
            Object (app: app, device: device, orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        }

        construct {
            var scroll = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vexpand = true
            };
            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 18) {
                margin_top = 24, margin_bottom = 24, margin_start = 24, margin_end = 24
            };
            scroll.child = content;
            append (scroll);

            /* ---- header ---- */
            var icon = new Gtk.Image.from_icon_name (device.device_type.icon_name ()) { pixel_size = 48 };
            var name = new Gtk.Label (device.name) {
                halign = Gtk.Align.START,
                ellipsize = Pango.EllipsizeMode.END
            };
            name.add_css_class (Granite.STYLE_CLASS_H1_LABEL);
            status_label = new Gtk.Label ("") {
                halign = Gtk.Align.START,
                ellipsize = Pango.EllipsizeMode.END
            };
            status_label.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            var title_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 3) { valign = Gtk.Align.CENTER, hexpand = true };
            title_box.append (name);
            title_box.append (status_label);

            pair_button = new Gtk.Button.with_label (_("Pair")) { valign = Gtk.Align.CENTER };
            pair_button.add_css_class (Granite.STYLE_CLASS_SUGGESTED_ACTION);
            pair_button.clicked.connect (on_pair_clicked);
            unpair_button = new Gtk.Button.with_label (_("Unpair")) { valign = Gtk.Align.CENTER };
            unpair_button.clicked.connect (() => device.unpair ());

            var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            header.append (icon);
            header.append (title_box);
            header.append (pair_button);
            header.append (unpair_button);
            content.append (header);

            /* ---- actions ---- */
            actions = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);

            var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var send_file = new Gtk.Button () { tooltip_text = _("Send files") };
            send_file.child = button_content ("document-send", _("Send Files…"));
            send_file.clicked.connect (on_send_files);
            var send_shot = new Gtk.Button () { tooltip_text = _("Take a screenshot and send it") };
            send_shot.child = button_content ("image-x-generic", _("Send Screenshot"));
            send_shot.clicked.connect (on_send_screenshot);
            var ping = new Gtk.Button () { tooltip_text = _("Ping") };
            ping.child = button_content ("network-transmit", _("Ping"));
            ping.clicked.connect (() => {
                if (app.ping.send_ping (device)) {
                    toast (_("Ping sent to %s").printf (device.name));
                }
            });
            buttons.append (send_file);
            buttons.append (send_shot);
            buttons.append (ping);
            actions.append (buttons);

            var text_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            text_box.add_css_class (Granite.STYLE_CLASS_LINKED);
            text_entry = new Gtk.Entry () {
                placeholder_text = _("Text or link to send to %s").printf (device.name),
                hexpand = true
            };
            text_entry.activate.connect (on_send_text);
            var send_text = new Gtk.Button.from_icon_name ("mail-send") { tooltip_text = _("Send") };
            send_text.clicked.connect (on_send_text);
            text_box.append (text_entry);
            text_box.append (send_text);
            actions.append (text_box);

            progress = new Gtk.ProgressBar () { visible = false, show_text = true };
            actions.append (progress);
            content.append (actions);

            /* ---- recent images ---- */
            var images_title = new Gtk.Label (_("Recent images")) { halign = Gtk.Align.START, hexpand = true };
            images_title.add_css_class (Granite.STYLE_CLASS_H3_LABEL);
            images_spinner = new Gtk.Spinner () { visible = false };
            images_refresh = new Gtk.Button.from_icon_name ("view-refresh") {
                tooltip_text = _("Fetch the newest photos and screenshots from the phone"),
                visible = Plugins.Sftp.supported_by (device)
            };
            images_refresh.add_css_class (Granite.STYLE_CLASS_FLAT);
            images_refresh.clicked.connect (() => {
                if (!app.gallery.refresh (device)) {
                    toast (_("%s is not reachable").printf (device.name));
                }
            });
            var images_header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            images_header.append (images_title);
            images_header.append (images_spinner);
            images_header.append (images_refresh);
            content.append (images_header);
            images_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            /* Only the gallery scrolls sideways; the rest of the page keeps a fixed minimum width. */
            var images_scroll = new Gtk.ScrolledWindow () {
                child = images_box,
                hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                vscrollbar_policy = Gtk.PolicyType.NEVER,
                propagate_natural_height = true
            };
            images_empty = new Gtk.Label (Plugins.Sftp.supported_by (device)
                ? _("The newest photos and screenshots on %s will show up here.").printf (device.name)
                : _("Images shared from %s will show up here.").printf (device.name)) {
                halign = Gtk.Align.START
            };
            images_empty.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            content.append (images_scroll);
            content.append (images_empty);

            /* ---- received items ---- */
            var items_title = new Gtk.Label (_("Received")) { halign = Gtk.Align.START };
            items_title.add_css_class (Granite.STYLE_CLASS_H3_LABEL);
            content.append (items_title);
            items_list = new Gtk.ListBox () { selection_mode = Gtk.SelectionMode.NONE };
            items_list.add_css_class (Granite.STYLE_CLASS_RICH_LIST);
            items_list.add_css_class (Granite.STYLE_CLASS_FRAME);
            items_list.bind_model (app.history.for_device (device.id), create_item_row);
            items_list.row_activated.connect ((row) => {
                var item = ((ItemRow) row).item;
                open_item (item);
            });
            content.append (items_list);

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
                    images_spinner.visible = is_busy;
                    images_spinner.spinning = is_busy;
                    images_refresh.sensitive = !is_busy;
                }
            });
            app.share.file_started.connect ((d, fname, size) => {
                if (d == device) {
                    progress.visible = true;
                    progress.fraction = 0;
                    progress.text = _("Receiving %s").printf (fname);
                }
            });
            app.share.file_progress.connect ((d, fname, done, size) => {
                if (d == device && size > 0) {
                    progress.fraction = (double) done / (double) size;
                }
            });
            app.share.file_received.connect ((d, f) => {
                if (d == device) {
                    progress.visible = false;
                    toast (_("Received %s").printf (f.get_basename ()));
                }
            });
            app.share.file_failed.connect ((d, fname, why) => {
                if (d == device) {
                    progress.visible = false;
                    toast (_("Failed to receive %s: %s").printf (fname, why));
                }
            });

            device.reachable_changed.connect (refresh);
            device.paired_changed.connect (refresh);
            device.pairing_failed.connect ((reason) => toast (_("Pairing failed: %s").printf (reason)));
            refresh ();
            refresh_images ();
        }

        private Gtk.Widget button_content (string icon_name, string label) {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            box.append (new Gtk.Image.from_icon_name (icon_name));
            box.append (new Gtk.Label (label));
            return box;
        }

        private void refresh () {
            bool paired = device.is_paired;
            bool reachable = device.is_reachable;
            if (!reachable) {
                status_label.label = paired ? _("Paired, currently offline") : _("Offline");
            } else if (paired) {
                status_label.label = _("Connected");
            } else if (device.pair_state == Core.PairState.REQUESTED) {
                status_label.label = _("Waiting for the device to accept…");
            } else if (device.pair_state == Core.PairState.REQUESTED_BY_PEER) {
                status_label.label = _("The device wants to pair");
            } else {
                status_label.label = _("Available on the network, not paired");
            }
            pair_button.visible = reachable && !paired;
            pair_button.sensitive = device.pair_state == Core.PairState.NOT_PAIRED
                                    || device.pair_state == Core.PairState.REQUESTED_BY_PEER;
            unpair_button.visible = paired;
            actions.sensitive = paired && reachable;
        }

        private void refresh_images () {
            Gtk.Widget? child;
            while ((child = images_box.get_first_child ()) != null) {
                images_box.remove (child);
            }
            /* Merge what the phone's gallery gave us with images it shared to us. */
            var merged = new GenericArray<Core.HistoryItem> ();
            foreach (var item in app.gallery.get_items (device.id)) {
                if (item.file_exists) {
                    merged.add (item);
                }
            }
            foreach (var item in app.history.recent_images (device.id, Gallery.MAX_IMAGES)) {
                merged.add (item);
            }
            merged.sort ((a, b) => (int) (b.time_ms - a.time_ms).clamp (-1, 1));
            Core.HistoryItem[] recent = {};
            for (uint i = 0; i < merged.length && i < Gallery.MAX_IMAGES; i++) {
                recent += merged[i];
            }
            images_empty.visible = recent.length == 0;
            images_refresh.visible = Plugins.Sftp.supported_by (device);
            foreach (var item in recent) {
                var picture = new Gtk.Picture.for_filename (item.value) {
                    content_fit = Gtk.ContentFit.COVER,
                    width_request = 120,
                    height_request = 120,
                    can_shrink = true
                };
                picture.add_css_class (Granite.STYLE_CLASS_CARD);
                picture.add_css_class (Granite.STYLE_CLASS_ROUNDED);
                var button = new Gtk.Button () {
                    child = picture,
                    tooltip_text = Path.get_basename (item.value)
                };
                button.add_css_class (Granite.STYLE_CLASS_FLAT);
                button.clicked.connect (() => open_item (item));
                make_draggable (button, item.value, picture);
                images_box.append (button);
            }
        }

        private Gtk.Widget create_item_row (Object obj) {
            return new ItemRow ((Core.HistoryItem) obj);
        }

        private void open_item (Core.HistoryItem item) {
            if (item.kind == Core.HistoryKind.TEXT) {
                Gdk.Display.get_default ().get_clipboard ().set_text (item.value);
                toast (_("Copied to clipboard"));
                return;
            }
            if (item.kind == Core.HistoryKind.FILE && !item.file_exists) {
                toast (_("%s no longer exists").printf (Path.get_basename (item.value)));
                return;
            }
            string uri = item.kind == Core.HistoryKind.FILE
                ? File.new_for_path (item.value).get_uri ()
                : item.value;
            /* Gtk.UriLauncher reports "The application launch failed" on Pantheon even
             * though GIO can launch the handler fine, so go through GIO directly. */
            var context = get_display ().get_app_launch_context ();
            AppInfo.launch_default_for_uri_async.begin (uri, context, null, (o, res) => {
                try {
                    AppInfo.launch_default_for_uri_async.end (res);
                } catch (Error e) {
                    toast (_("Could not open %s: %s").printf (Path.get_basename (item.value), e.message));
                }
            });
        }

        /** Lets a file be dragged out of the window into other applications. */
        public static void make_draggable (Gtk.Widget widget, string path, Gtk.Widget? icon_source) {
            var source = new Gtk.DragSource () { actions = Gdk.DragAction.COPY };
            source.prepare.connect ((x, y) => {
                var file = File.new_for_path (path);
                if (!file.query_exists ()) {
                    return null;
                }
                if (icon_source != null) {
                    source.set_icon (new Gtk.WidgetPaintable (icon_source), (int) x, (int) y);
                }
                var value = Value (typeof (File));
                value.set_object (file);
                return new Gdk.ContentProvider.union ({
                    new Gdk.ContentProvider.for_value (new Gdk.FileList.from_array ({ file })),
                    new Gdk.ContentProvider.for_value (value)
                });
            });
            widget.add_controller (source);
        }

        /* ---- actions ---- */

        private void on_pair_clicked () {
            bool incoming = device.pair_state == Core.PairState.REQUESTED_BY_PEER;
            if (!incoming && !device.request_pairing ()) {
                return;
            }
            var dialog = new PairDialog (get_root () as Gtk.Window, device, incoming);
            dialog.present ();
        }

        public void show_incoming_pair_request () {
            var dialog = new PairDialog (get_root () as Gtk.Window, device, true);
            dialog.present ();
        }

        private void on_send_text () {
            string text = text_entry.text.strip ();
            if (text == "") {
                return;
            }
            bool ok;
            bool looks_like_url = false;
            try {
                looks_like_url = (text.has_prefix ("http://") || text.has_prefix ("https://"))
                                 && Uri.is_valid (text, UriFlags.NONE);
            } catch (Error e) {
                looks_like_url = false;
            }
            if (looks_like_url) {
                ok = app.share.send_url (device, text);
            } else {
                ok = app.share.send_text (device, text);
            }
            if (ok) {
                text_entry.text = "";
                toast (_("Sent to %s").printf (device.name));
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
                    var file = Screenshot.take.end (res);
                    send_file (file);
                } catch (Error e) {
                    if (!(e is IOError.CANCELLED)) {
                        toast (e.message);
                    }
                }
            });
        }

        private void send_file (File file) {
            progress.visible = true;
            progress.fraction = 0;
            progress.pulse ();
            progress.text = _("Sending %s").printf (file.get_basename ());
            uint pulse = Timeout.add (150, () => { progress.pulse (); return Source.CONTINUE; });
            app.share.send_file.begin (device, file, null, (obj, res) => {
                Source.remove (pulse);
                progress.visible = false;
                try {
                    app.share.send_file.end (res);
                    toast (_("Sent %s").printf (file.get_basename ()));
                    app.history.add (device.id, new Core.HistoryItem (Core.HistoryKind.FILE, file.get_path (), false));
                } catch (Error e) {
                    toast (_("Sending %s failed: %s").printf (file.get_basename (), e.message));
                }
            });
        }
    }

    private class ItemRow : Gtk.ListBoxRow {
        public Core.HistoryItem item { get; construct; }

        public ItemRow (Core.HistoryItem item) {
            Object (item: item);
        }

        construct {
            string icon_name;
            string text;
            switch (item.kind) {
                case Core.HistoryKind.TEXT:
                    icon_name = "edit-paste";
                    text = item.value.replace ("\n", " ");
                    break;
                case Core.HistoryKind.URL:
                    icon_name = "web-browser";
                    text = item.value;
                    break;
                default:
                    icon_name = item.is_image ? "image-x-generic" : "text-x-generic";
                    text = Path.get_basename (item.value);
                    break;
            }
            var when = new DateTime.from_unix_local (item.time_ms / 1000);
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            box.append (new Gtk.Image.from_icon_name (icon_name));
            var label = new Gtk.Label (text) {
                halign = Gtk.Align.START,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END,
                width_chars = 10,
                max_width_chars = 60
            };
            box.append (label);
            var direction = new Gtk.Image.from_icon_name (item.incoming ? "go-down" : "go-up") {
                tooltip_text = item.incoming ? _("Received") : _("Sent")
            };
            direction.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            box.append (direction);
            var time_label = new Gtk.Label (when.format ("%x %H:%M"));
            time_label.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            time_label.add_css_class (Granite.STYLE_CLASS_SMALL_LABEL);
            box.append (time_label);
            child = box;
            activatable = true;
            if (item.kind == Core.HistoryKind.FILE) {
                DevicePage.make_draggable (this, item.value, null);
            }
        }
    }
}
