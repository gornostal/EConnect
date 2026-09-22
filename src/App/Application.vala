/*
 * SPDX-License-Identifier: MIT
 */
namespace EConnect.App {

    public class Application : Gtk.Application {
        public Core.Daemon daemon { get; private set; }
        public Core.History history { get; private set; }
        public Plugins.Ping ping { get; private set; }
        public Plugins.Share share { get; private set; }
        public ClipboardPlugin clipboard { get; private set; }
        public Plugins.Sftp sftp { get; private set; }
        public Gallery gallery { get; private set; }

        private string? startup_error = null;

        public Application () {
            Object (application_id: APP_ID, flags: ApplicationFlags.DEFAULT_FLAGS);
        }

        protected override void startup () {
            base.startup ();
            Granite.init ();

            var granite_settings = Granite.Settings.get_default ();
            var gtk_settings = Gtk.Settings.get_default ();
            gtk_settings.gtk_application_prefer_dark_theme =
                granite_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
            granite_settings.notify["prefers-color-scheme"].connect (() => {
                gtk_settings.gtk_application_prefer_dark_theme =
                    granite_settings.prefers_color_scheme == Granite.Settings.ColorScheme.DARK;
            });

            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (quit);
            add_action (quit_action);
            set_accels_for_action ("app.quit", { "<Control>q" });

            try {
                var config = new Core.Config ();
                daemon = new Core.Daemon (config);
                history = new Core.History (config);
                ping = new Plugins.Ping ();
                share = new Plugins.Share ();
                clipboard = new ClipboardPlugin (Gdk.Display.get_default ());
                sftp = new Plugins.Sftp ();
                daemon.add_plugin (ping);
                daemon.add_plugin (share);
                daemon.add_plugin (clipboard);
                daemon.add_plugin (sftp);
                gallery = new Gallery (this);
                daemon.device_changed.connect ((d) => {
                    if (d.is_paired && d.is_reachable) {
                        gallery.refresh (d);
                    }
                });
                wire_history ();
                daemon.start ();
            } catch (Error e) {
                startup_error = e.message;
                critical ("Startup failed: %s", e.message);
            }
        }

        private void wire_history () {
            share.text_received.connect ((d, text) => {
                history.add (d.id, new Core.HistoryItem (Core.HistoryKind.TEXT, text, true));
            });
            share.url_received.connect ((d, url) => {
                history.add (d.id, new Core.HistoryItem (Core.HistoryKind.URL, url, true));
            });
            share.file_received.connect ((d, file) => {
                history.add (d.id, new Core.HistoryItem (Core.HistoryKind.FILE, file.get_path (), true));
                var n = new Notification (_("Received from %s").printf (d.name));
                n.set_body (file.get_basename ());
                n.set_icon (new ThemedIcon ("document-save"));
                send_notification ("file-" + file.get_basename (), n);
            });
        }

        protected override void activate () {
            if (startup_error != null) {
                var dialog = new Granite.MessageDialog.with_image_from_icon_name (
                    _("EConnect could not start"), startup_error, "dialog-error", Gtk.ButtonsType.CLOSE);
                dialog.response.connect (() => quit ());
                dialog.present ();
                return;
            }
            if (active_window == null) {
                new MainWindow (this);
            }
            active_window.present ();
        }

        protected override void shutdown () {
            if (daemon != null) {
                daemon.stop ();
            }
            base.shutdown ();
        }

        public static int main (string[] args) {
            Intl.setlocale (LocaleCategory.ALL, "");
            Intl.bindtextdomain (APP_ID, null);
            Intl.textdomain (APP_ID);
            return new Application ().run (args);
        }
    }
}
