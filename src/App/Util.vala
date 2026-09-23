/*
 * SPDX-License-Identifier: MIT
 *
 * Small helpers shared by the window, device pages and notifications.
 */
namespace EConnect.App.Util {

    /** Opens a file or URL in its default app. */
    public async void open_uri (string uri, Gtk.Window? parent) throws Error {
        /* Gtk.UriLauncher reports "The application launch failed" on Pantheon even
         * though GIO can launch the handler fine, so go through GIO directly. */
        var display = parent != null ? parent.get_display () : Gdk.Display.get_default ();
        yield AppInfo.launch_default_for_uri_async (uri, display.get_app_launch_context (), null);
    }

    /** Opens the file manager with the file selected. */
    public async void show_in_folder (File file, Gtk.Window? parent) throws Error {
        var launcher = new Gtk.FileLauncher (file);
        yield launcher.open_containing_folder (parent, null);
    }

    /** Symbolic icons take the text color, so the avatar can tint them. */
    public string device_icon (Core.DeviceType type) {
        switch (type) {
            case Core.DeviceType.PHONE: return "phone-symbolic";
            case Core.DeviceType.TABLET: return "tablet-symbolic";
            case Core.DeviceType.TV: return "video-display-symbolic";
            case Core.DeviceType.LAPTOP: return "computer-laptop-symbolic";
            default: return "computer-symbolic";
        }
    }

    /** "connected", "available", "pairing" or "offline": CSS classes for avatars and pills. */
    public string device_state (Core.Device device) {
        var state = device.pair_state;
        if (state == Core.PairState.REQUESTED || state == Core.PairState.REQUESTED_BY_PEER) {
            return "pairing";
        }
        if (!device.is_reachable) {
            return "offline";
        }
        return device.is_paired ? "connected" : "available";
    }

    public string time_format () {
        /* Locales with a 24-hour clock have no AM/PM designator. */
        bool is_12h = new GLib.DateTime.now_local ().format ("%p") != "";
        return Granite.DateTime.get_default_time_format (is_12h);
    }

    /** "Today", "Yesterday", or a date, for grouping lists by day. */
    public string day_label (int64 time_ms) {
        var when = new GLib.DateTime.from_unix_local (time_ms / 1000);
        var today = new GLib.DateTime.now_local ();
        if (Granite.DateTime.is_same_day (when, today)) {
            return _("Today");
        }
        if (Granite.DateTime.is_same_day (when, today.add_days (-1))) {
            return _("Yesterday");
        }
        bool this_year = when.get_year () == today.get_year ();
        return when.format (Granite.DateTime.get_default_date_format (true, true, !this_year));
    }

    public bool same_day (int64 a_ms, int64 b_ms) {
        return Granite.DateTime.is_same_day (new GLib.DateTime.from_unix_local (a_ms / 1000),
                                             new GLib.DateTime.from_unix_local (b_ms / 1000));
    }

    /** Lets a file be dragged out of the window into other applications. */
    public void make_draggable (Gtk.Widget widget, string path, Gtk.Widget? icon_source) {
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
}
