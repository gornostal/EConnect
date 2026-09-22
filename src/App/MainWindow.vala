/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
namespace EConnect.App {

    public class MainWindow : Gtk.ApplicationWindow {
        public Application app { get; construct; }

        private Gtk.ListBox device_list;
        private Gtk.Stack stack;
        private Granite.Placeholder placeholder;
        private Granite.Toast toast;
        private HashTable<string, DeviceRow> rows = new HashTable<string, DeviceRow> (str_hash, str_equal);
        private HashTable<string, DevicePage> pages = new HashTable<string, DevicePage> (str_hash, str_equal);

        public MainWindow (Application app) {
            Object (application: app, app: app, title: _("EConnect"), default_width: 900, default_height: 600);
        }

        construct {
            var header = new Gtk.HeaderBar () { show_title_buttons = true };
            header.add_css_class (Granite.STYLE_CLASS_FLAT);
            var refresh = new Gtk.Button.from_icon_name ("view-refresh") {
                tooltip_text = _("Look for devices again")
            };
            refresh.clicked.connect (() => {
                app.daemon.refresh ();
                toast.title = _("Looking for devices on the network…");
                toast.send_notification ();
            });
            header.pack_end (refresh);
            var me = new Gtk.Label (_("This device: %s").printf (app.daemon.config.device_name));
            me.add_css_class (Granite.STYLE_CLASS_DIM_LABEL);
            header.pack_start (me);
            titlebar = header;

            device_list = new Gtk.ListBox () {
                selection_mode = Gtk.SelectionMode.SINGLE,
                width_request = 260
            };
            device_list.add_css_class (Granite.STYLE_CLASS_SIDEBAR);
            device_list.row_selected.connect ((row) => {
                if (row != null) {
                    stack.visible_child = pages.lookup (((DeviceRow) row).device.id);
                }
            });
            var side_scroll = new Gtk.ScrolledWindow () {
                child = device_list,
                hscrollbar_policy = Gtk.PolicyType.NEVER
            };

            placeholder = new Granite.Placeholder (_("No devices yet")) {
                description = _("Open KDE Connect on your phone while it is on the same Wi-Fi network. Devices appear here automatically."),
                icon = new ThemedIcon ("network-wireless")
            };
            stack = new Gtk.Stack () { hexpand = true };
            stack.add_named (placeholder, "placeholder");

            var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
                start_child = side_scroll,
                end_child = stack,
                shrink_start_child = false,
                resize_start_child = false,
                position = 260
            };

            toast = new Granite.Toast ("");
            var overlay = new Gtk.Overlay () { child = paned };
            overlay.add_overlay (toast);
            child = overlay;

            foreach (var device in app.daemon.get_devices ()) {
                add_device (device);
            }
            app.daemon.device_added.connect (add_device);
            app.daemon.device_removed.connect (remove_device);
            app.ping.ping_received.connect ((d, msg) => show_toast (
                msg != null ? _("Ping from %s: %s").printf (d.name, msg) : _("Ping from %s").printf (d.name)));
            app.clipboard.clipboard_received.connect ((d, text) => show_toast (_("Clipboard updated from %s").printf (d.name)));
            app.share.text_received.connect ((d, text) => show_toast (_("Text from %s").printf (d.name)));
            app.share.url_received.connect ((d, url) => show_toast (_("Link from %s").printf (d.name)));
        }

        private void show_toast (string message) {
            toast.title = message;
            toast.send_notification ();
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
            pages.insert (device.id, page);
            stack.add_named (page, device.id);

            device.pair_request.connect (() => {
                device_list.select_row (row);
                page.show_incoming_pair_request ();
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
                stack.visible_child = placeholder;
            } else if (device_list.get_selected_row () == null) {
                device_list.select_row (device_list.get_row_at_index (0));
            }
        }
    }
}
