/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Take a screenshot through the org.freedesktop.portal.Screenshot portal.
 */
namespace EConnect.App.Screenshot {

    public async File take (Gtk.Window? parent, bool interactive) throws Error {
        var bus = yield Bus.get (BusType.SESSION);
        string token = "econnect%u".printf (Random.next_int ());
        string sender = bus.get_unique_name ().substring (1).replace (".", "_");
        string expected_path = "/org/freedesktop/portal/desktop/request/%s/%s".printf (sender, token);

        uint? response_code = null;
        string? uri = null;
        SourceFunc resume = take.callback;
        uint sub = bus.signal_subscribe (
            "org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request", "Response",
            expected_path, null, DBusSignalFlags.NO_MATCH_RULE,
            (conn, sender_name, path, iface, signal_name, parameters) => {
                uint code;
                Variant results;
                parameters.get ("(u@a{sv})", out code, out results);
                response_code = code;
                var v = results.lookup_value ("uri", VariantType.STRING);
                if (v != null) {
                    uri = v.get_string ();
                }
                Idle.add ((owned) resume);
            });

        var options = new VariantBuilder (VariantType.VARDICT);
        options.add ("{sv}", "handle_token", new Variant.string (token));
        options.add ("{sv}", "interactive", new Variant.boolean (interactive));
        options.add ("{sv}", "modal", new Variant.boolean (true));

        string parent_handle = "";
        Variant reply = yield bus.call (
            "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.Screenshot", "Screenshot",
            new Variant ("(sa{sv})", parent_handle, options),
            new VariantType ("(o)"), DBusCallFlags.NONE, -1);
        string handle;
        reply.get ("(o)", out handle);
        if (handle != expected_path) {
            /* Older portals return a different path; re-subscribe on the real one. */
            bus.signal_unsubscribe (sub);
            sub = bus.signal_subscribe (
                "org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request", "Response",
                handle, null, DBusSignalFlags.NO_MATCH_RULE,
                (conn, sender_name, path, iface, signal_name, parameters) => {
                    uint code;
                    Variant results;
                    parameters.get ("(u@a{sv})", out code, out results);
                    response_code = code;
                    var v = results.lookup_value ("uri", VariantType.STRING);
                    if (v != null) {
                        uri = v.get_string ();
                    }
                    Idle.add ((owned) resume);
                });
        }

        yield;
        bus.signal_unsubscribe (sub);

        if (response_code != 0) {
            throw new IOError.CANCELLED (_("Screenshot cancelled"));
        }
        if (uri == null) {
            throw new IOError.FAILED (_("The screenshot portal returned no image"));
        }
        return File.new_for_uri (uri);
    }
}
