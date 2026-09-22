/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * econnect-cli: headless test driver for the core. Discovers devices, pairs
 * and pings from an interactive prompt.
 */
namespace EConnect.Cli {

    private static string? opt_config_dir = null;
    private static string? opt_name = null;
    private static bool opt_verbose = false;

    private const OptionEntry[] OPTIONS = {
        { "config-dir", 'c', OptionFlags.NONE, OptionArg.FILENAME, ref opt_config_dir,
          "Use this directory for identity and pairings", "DIR" },
        { "name", 'n', OptionFlags.NONE, OptionArg.STRING, ref opt_name,
          "Device name to announce", "NAME" },
        { "verbose", 'v', OptionFlags.NONE, OptionArg.NONE, ref opt_verbose,
          "Print debug output", null },
        { null }
    };

    private Core.Device[] listed;

    private void list_devices (Core.Daemon daemon) {
        listed = {};
        foreach (var dev in daemon.get_devices ()) {
            listed += dev;
        }
        if (listed.length == 0) {
            print ("No devices. Open KDE Connect on the phone and type 'refresh'.\n");
            return;
        }
        for (int i = 0; i < listed.length; i++) {
            var d = listed[i];
            print ("  [%d] %-24s %-7s %-12s %s\n", i, d.name, d.device_type.to_string (),
                   d.is_reachable ? "reachable" : "offline", d.pair_state.to_string ());
        }
    }

    private Core.Device? pick (string[] words) {
        if (words.length < 2) {
            print ("Usage: <command> <index>. Type 'list' first.\n");
            return null;
        }
        int idx = int.parse (words[1]);
        if (idx < 0 || idx >= listed.length) {
            print ("No device with index %d. Type 'list'.\n", idx);
            return null;
        }
        return listed[idx];
    }

    private Plugins.Share share;

    private void handle_command (Core.Daemon daemon, Plugins.Ping ping, string line, MainLoop loop) {
        string[] words = line.strip ().split (" ", 3);
        if (words.length == 0 || words[0] == "") {
            return;
        }
        switch (words[0]) {
            case "help":
            case "?":
                print ("Commands: list | refresh | pair N | accept N | reject N | unpair N | ping N [msg]\n          sendfile N PATH | sendtext N TEXT | sendurl N URL | downloads DIR | id | quit\n");
                break;
            case "list":
            case "ls":
                list_devices (daemon);
                break;
            case "refresh":
                daemon.refresh ();
                print ("Broadcast sent.\n");
                break;
            case "id":
                print ("Device id: %s\nName: %s\nTCP port: %u\nCertificate SHA256: %s\n",
                       daemon.config.device_id, daemon.config.device_name,
                       daemon.link_provider.tcp_port,
                       Core.Certificate.fingerprint (daemon.config.certificate));
                break;
            case "pair": {
                var d = pick (words);
                if (d != null && d.request_pairing ()) {
                    print ("Pairing requested. Verification code: %s\n", d.verification_key () ?? "?");
                    print ("Confirm the same code on %s.\n", d.name);
                }
                break;
            }
            case "accept": {
                var d = pick (words);
                if (d != null) {
                    print (d.accept_pairing () ? "Accepted.\n" : "Nothing to accept.\n");
                }
                break;
            }
            case "reject": {
                var d = pick (words);
                if (d != null) {
                    d.reject_pairing ();
                }
                break;
            }
            case "unpair": {
                var d = pick (words);
                if (d != null) {
                    d.unpair ();
                }
                break;
            }
            case "ping": {
                var d = pick (words);
                if (d != null) {
                    string? msg = words.length > 2 ? words[2] : null;
                    print (ping.send_ping (d, msg) ? "Ping sent.\n" : "Device not reachable.\n");
                }
                break;
            }
            case "sendfile": {
                var d = pick (words);
                if (d != null && words.length > 2) {
                    var f = File.new_for_commandline_arg (words[2]);
                    share.send_file.begin (d, f, null, (obj, res) => {
                        try {
                            share.send_file.end (res);
                            print ("\nFile sent.\n> ");
                        } catch (Error e) {
                            print ("\nSend failed: %s\n> ", e.message);
                        }
                    });
                }
                break;
            }
            case "sendtext": {
                var d = pick (words);
                if (d != null && words.length > 2) {
                    print (share.send_text (d, words[2]) ? "Text sent.\n" : "Device not reachable.\n");
                }
                break;
            }
            case "sendurl": {
                var d = pick (words);
                if (d != null && words.length > 2) {
                    print (share.send_url (d, words[2]) ? "URL sent.\n" : "Device not reachable.\n");
                }
                break;
            }
            case "downloads":
                if (words.length > 1) {
                    share.download_dir = File.new_for_commandline_arg (words[1]);
                }
                print ("Downloads go to %s\n", share.download_dir.get_path ());
                break;
            case "quit":
            case "exit":
                loop.quit ();
                break;
            default:
                print ("Unknown command '%s'. Type 'help'.\n", words[0]);
                break;
        }
    }

    private async void read_commands (Core.Daemon daemon, Plugins.Ping ping, MainLoop loop) {
        var input = new DataInputStream (new UnixInputStream (0, false));
        while (true) {
            print ("> ");
            string? line = null;
            try {
                line = yield input.read_line_async ();
            } catch (Error e) {
                break;
            }
            if (line == null) {
                break;
            }
            handle_command (daemon, ping, line, loop);
        }
        loop.quit ();
    }

    public static int main (string[] args) {
        try {
            var ctx = new OptionContext ("- KDE Connect compatible test client");
            ctx.add_main_entries (OPTIONS, null);
            ctx.parse (ref args);
        } catch (OptionError e) {
            printerr ("%s\n", e.message);
            return 1;
        }
        if (opt_verbose) {
            Environment.set_variable ("G_MESSAGES_DEBUG", "all", true);
        }

        var loop = new MainLoop ();
        Core.Daemon daemon;
        try {
            var config = new Core.Config (opt_config_dir, opt_name);
            daemon = new Core.Daemon (config);
        } catch (Error e) {
            printerr ("Cannot initialise: %s\n", e.message);
            return 1;
        }

        var ping = new Plugins.Ping ();
        daemon.add_plugin (ping);
        share = new Plugins.Share ();
        daemon.add_plugin (share);
        share.text_received.connect ((d, text) => print ("\n*** Text from %s: %s\n> ", d.name, text));
        share.url_received.connect ((d, url) => print ("\n*** URL from %s: %s\n> ", d.name, url));
        share.file_started.connect ((d, name, size) => print ("\n*** Receiving %s (%s bytes) from %s\n> ", name, size.to_string (), d.name));
        share.file_received.connect ((d, f) => print ("\n*** Saved %s\n> ", f.get_path ()));
        share.file_failed.connect ((d, name, why) => print ("\n*** Failed to receive %s: %s\n> ", name, why));
        ping.ping_received.connect ((d, msg) => {
            print ("\n*** Ping from %s%s\n> ", d.name, msg != null ? ": " + msg : "");
        });

        daemon.device_added.connect ((d) => {
            print ("\n+ Device %s (%s) %s\n> ", d.name, d.device_type.to_string (), d.pair_state.to_string ());
            d.pair_request.connect (() => {
                print ("\n*** %s wants to pair. Verification code: %s\n    Type 'list' then 'accept N' or 'reject N'.\n> ",
                       d.name, d.verification_key () ?? "?");
            });
            d.paired_changed.connect (() => {
                print ("\n* %s is now %s\n> ", d.name, d.pair_state.to_string ());
            });
            d.pairing_failed.connect ((reason) => {
                print ("\n* Pairing with %s failed: %s\n> ", d.name, reason);
            });
            d.reachable_changed.connect (() => {
                print ("\n* %s is %s\n> ", d.name, d.is_reachable ? "reachable" : "offline");
            });
        });
        daemon.device_removed.connect ((d) => {
            print ("\n- Device %s went away\n> ", d.name);
        });

        try {
            daemon.start ();
        } catch (Error e) {
            printerr ("Cannot start: %s\n", e.message);
            return 1;
        }

        print ("EConnect CLI. I am '%s' (%s), TCP %u. Type 'help'.\n",
               daemon.config.device_name, daemon.config.device_id, daemon.link_provider.tcp_port);
        read_commands.begin (daemon, ping, loop);
        loop.run ();
        daemon.stop ();
        return 0;
    }
}
