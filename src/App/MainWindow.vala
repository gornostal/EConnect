/*
 * SPDX-License-Identifier: MIT
 */
namespace EConnect.App {

    public delegate void UndoFunc ();

    public class MainWindow : Gtk.ApplicationWindow {
        public Application app { get; construct; }

        private Gtk.ListBox device_list;
        private Gtk.Stack stack;
        private Granite.Toast toast;
        private Granite.Toast undo_toast;
        private UndoFunc? pending_undo = null;
        private Gtk.EditableLabel name_label;
        private EmptyState empty_state;
        private HashTable<string, DeviceRow> rows = new HashTable<string, DeviceRow> (str_hash, str_equal);
        private HashTable<string, DevicePage> pages = new HashTable<string, DevicePage> (str_hash, str_equal);

        public MainWindow (Application app) {
            Object (application: app, app: app, title: _("EConnect"),
                    default_width: 960, default_height: 680,
                    width_request: 720, height_request: 480);
        }

        construct {
            /* ---- sidebar ---- */
            var refresh = new Gtk.Button.from_icon_name ("view-refresh") {
                tooltip_text = _("Look for devices again")
            };
            refresh.clicked.connect (search_again);

            var side_header = new Gtk.HeaderBar () {
                show_title_buttons = false,
                title_widget = new Gtk.Label ("")
            };
            side_header.add_css_class (Granite.STYLE_CLASS_FLAT);
            side_header.pack_start (new Gtk.WindowControls (Gtk.PackType.START));
            side_header.pack_end (refresh);

            device_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.SINGLE,
                vexpand = true
            };
            device_list.add_css_class ("device-list");
            device_list.set_placeholder (build_searching_row ());
            device_list.set_sort_func (sort_rows);
            device_list.set_header_func (update_header);
            device_list.row_selected.connect ((row) => {
                if (row != null) {
                    stack.visible_child = pages.lookup (((DeviceRow) row).device.id);
                }
            });
            var side_scroll = new Gtk.ScrolledWindow () {
                child = device_list,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vexpand = true
            };

            var sidebar = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { width_request = 240 };
            sidebar.add_css_class (Granite.STYLE_CLASS_SIDEBAR);
            sidebar.append (side_header);
            sidebar.append (side_scroll);
            sidebar.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            sidebar.append (build_this_computer ());

            /* ---- content ---- */
            var main_header = new Gtk.HeaderBar () {
                show_title_buttons = false,
                title_widget = new Gtk.Label ("")
            };
            main_header.add_css_class (Granite.STYLE_CLASS_FLAT);
            main_header.pack_end (new Gtk.WindowControls (Gtk.PackType.END));

            stack = new Gtk.Stack () { hexpand = true, vexpand = true };
            stack.add_named (build_placeholder (), "placeholder");

            toast = new Granite.Toast ("");
            undo_toast = new Granite.Toast ("");
            undo_toast.set_default_action (_("Undo"));
            undo_toast.default_action.connect (() => {
                if (pending_undo != null) {
                    pending_undo ();
                    pending_undo = null;
                }
            });
            var overlay = new Gtk.Overlay () { child = stack };
            overlay.add_overlay (toast);
            overlay.add_overlay (undo_toast);

            var main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            main_box.append (main_header);
            main_box.append (overlay);

            var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
                start_child = sidebar,
                end_child = main_box,
                shrink_start_child = false,
                resize_start_child = false,
                position = 240
            };
            child = paned;
            /* The header bars live inside the panes; hide the default title bar. */
            titlebar = new Gtk.Grid () { visible = false };

            foreach (var device in app.daemon.get_devices ()) {
                add_device (device);
            }
            app.daemon.device_added.connect (add_device);
            app.daemon.device_removed.connect (remove_device);
            app.ping.ping_received.connect ((d, msg) => show_toast (
                msg != null ? _("Ping from %s: %s").printf (d.name, msg) : _("Ping from %s").printf (d.name)));
            app.share.text_received.connect ((d, text) => show_toast (_("Text from %s").printf (d.name)));
            app.share.url_received.connect ((d, url) => show_toast (_("Link from %s").printf (d.name)));
        }

        private Gtk.Widget build_searching_row () {
            var dot = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                halign = Gtk.Align.CENTER,
                valign = Gtk.Align.CENTER,
                hexpand = true,
                vexpand = true
            };
            var radar = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { valign = Gtk.Align.CENTER };
            radar.add_css_class ("mini-radar");
            radar.append (dot);
            radar.hexpand = radar.vexpand = false;
            var label = new Gtk.Label (_("Looking on this network…")) { xalign = 0 };
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) { valign = Gtk.Align.START };
            box.add_css_class ("searching");
            box.append (radar);
            box.append (label);
            return box;
        }

        private Gtk.Widget build_this_computer () {
            var icon = new Gtk.Image.from_icon_name ("computer-symbolic") { hexpand = true, vexpand = true };
            var icon_tile = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { valign = Gtk.Align.CENTER };
            icon_tile.add_css_class ("me-icon");
            icon_tile.append (icon);
            icon_tile.hexpand = icon_tile.vexpand = false;
            var caption = new Gtk.Label (_("This computer, visible as")) { halign = Gtk.Align.START };
            caption.add_css_class (Granite.STYLE_CLASS_SMALL_LABEL);
            caption.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            name_label = new Gtk.EditableLabel (app.daemon.config.device_name) {
                tooltip_text = _("The name other devices see"),
                hexpand = true
            };
            name_label.notify["editing"].connect (() => {
                if (!name_label.editing) {
                    save_name ();
                }
            });
            var text = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { valign = Gtk.Align.CENTER, hexpand = true };
            text.append (caption);
            text.append (name_label);

            var edit = new Gtk.Button.from_icon_name ("edit-symbolic") {
                tooltip_text = _("Rename this computer"),
                valign = Gtk.Align.CENTER
            };
            edit.add_css_class (Granite.STYLE_CLASS_FLAT);
            edit.clicked.connect (() => name_label.start_editing ());

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            box.add_css_class ("me-card");
            box.append (icon_tile);
            box.append (text);
            box.append (edit);
            return box;
        }

        private void save_name () {
            string name = name_label.text.strip ();
            if (name == "" || name == app.daemon.config.device_name) {
                name_label.text = app.daemon.config.device_name;
                return;
            }
            try {
                app.daemon.rename (name);
                name_label.text = app.daemon.config.device_name;
                empty_state.set_computer_name (app.daemon.config.device_name);
                show_toast (_("Renamed. Connected devices see the new name after they reconnect."));
            } catch (Error e) {
                name_label.text = app.daemon.config.device_name;
                show_toast (_("Could not rename this computer: %s").printf (e.message));
            }
        }

        private Gtk.Widget build_placeholder () {
            empty_state = new EmptyState ();
            empty_state.set_computer_name (app.daemon.config.device_name);
            empty_state.search_again.connect (search_again);
            empty_state.get_app.connect (() => {
                Util.open_uri.begin ("https://kdeconnect.kde.org/download.html", this, (o, res) => {
                    try {
                        Util.open_uri.end (res);
                    } catch (Error e) {
                        show_toast (e.message);
                    }
                });
            });
            return new Gtk.ScrolledWindow () {
                child = empty_state,
                hscrollbar_policy = Gtk.PolicyType.NEVER
            };
        }

        private void search_again () {
            app.daemon.refresh ();
            show_toast (_("Looking for devices on the network…"));
        }

        public void show_toast (string message) {
            undo_toast.withdraw ();
            toast.title = message;
            toast.send_notification ();
        }

        public void show_undo_toast (string message, owned UndoFunc undo) {
            toast.withdraw ();
            pending_undo = (owned) undo;
            undo_toast.title = message;
            undo_toast.send_notification ();
        }

        private int sort_rows (Gtk.ListBoxRow a, Gtk.ListBoxRow b) {
            var da = ((DeviceRow) a).device;
            var db = ((DeviceRow) b).device;
            if (da.is_paired != db.is_paired) {
                return da.is_paired ? -1 : 1;
            }
            return da.name.collate (db.name);
        }

        private void update_header (Gtk.ListBoxRow row, Gtk.ListBoxRow? before) {
            bool paired = ((DeviceRow) row).device.is_paired;
            if (before != null && ((DeviceRow) before).device.is_paired == paired) {
                row.set_header (null);
                return;
            }
            var header = row.get_header () as Gtk.Label;
            string label = (paired ? _("My Devices") : _("Nearby")).up ();
            if (header == null) {
                header = new Gtk.Label (label) { xalign = 0 };
                header.add_css_class ("group-label");
                row.set_header (header);
            } else {
                header.label = label;
            }
        }

        private void add_device (Core.Device device) {
            if (rows.contains (device.id)) {
                return;
            }
            var row = new DeviceRow (device);
            rows.insert (device.id, row);
            device_list.append (row);

            var page = new DevicePage (app, device);
            page.toast.connect (show_toast);
            page.busy_changed.connect ((text) => row.busy_text = text);
            pages.insert (device.id, page);
            stack.add_named (page, device.id);

            device.paired_changed.connect (() => {
                device_list.invalidate_sort ();
                device_list.invalidate_headers ();
            });
            device.pair_request.connect (() => {
                device_list.select_row (row);
                page.show_incoming_pair_request ();
                if (!is_active) {
                    var n = new Notification (_("%s wants to pair").printf (device.name));
                    n.set_body (_("Compare the code on both screens before accepting."));
                    n.set_icon (new ThemedIcon (device.device_type.icon_name ()));
                    app.send_notification ("pair-" + device.id, n);
                }
            });

            if (device_list.get_selected_row () == null) {
                device_list.select_row (row);
            }
        }

        private void remove_device (Core.Device device) {
            var row = rows.lookup (device.id);
            if (row != null) {
                device_list.remove (row);
                rows.remove (device.id);
            }
            var page = pages.lookup (device.id);
            if (page != null) {
                stack.remove (page);
                pages.remove (device.id);
            }
            if (rows.size () == 0) {
                stack.visible_child_name = "placeholder";
            } else if (device_list.get_selected_row () == null) {
                device_list.select_row (device_list.get_row_at_index (0));
            }
        }
    }
}
