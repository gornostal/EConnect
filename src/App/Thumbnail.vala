/*
 * SPDX-License-Identifier: MIT
 *
 * A square image preview. Loads a scaled-down copy in the background (phone
 * photos are often 12 MP) and fills its area the way CSS "cover" does.
 */
namespace EConnect.App {

    public class Thumbnail : Gtk.Widget {
        private const int LOAD_SIZE = 320;
        private static HashTable<string, Gdk.Texture>? cache = null;

        public string path { get; construct; }
        public int natural_size { get; construct; }

        private Gdk.Texture? texture = null;

        public Thumbnail (string path, int natural_size) {
            Object (path: path, natural_size: natural_size, overflow: Gtk.Overflow.HIDDEN);
        }

        construct {
            if (cache == null) {
                cache = new HashTable<string, Gdk.Texture> (str_hash, str_equal);
            }
            texture = cache.lookup (path);
            if (texture == null) {
                load.begin ();
            }
        }

        private async void load () {
            try {
                var stream = yield File.new_for_path (path).read_async ();
                var pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async (stream, LOAD_SIZE, LOAD_SIZE, true, null);
                pixbuf = pixbuf.apply_embedded_orientation ();
                texture = Gdk.Texture.for_pixbuf (pixbuf);
                cache.insert (path, texture);
                queue_draw ();
            } catch (Error e) {
                debug ("thumbnail %s: %s", path, e.message);
            }
        }

        public override Gtk.SizeRequestMode get_request_mode () {
            return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH;
        }

        public override void measure (Gtk.Orientation orientation, int for_size,
                                      out int minimum, out int natural,
                                      out int minimum_baseline, out int natural_baseline) {
            minimum_baseline = natural_baseline = -1;
            if (orientation == Gtk.Orientation.HORIZONTAL) {
                minimum = int.min (natural_size, 48);
                natural = natural_size;
            } else {
                /* Square: as tall as it is wide. */
                minimum = natural = for_size > 0 ? for_size : natural_size;
            }
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            if (texture == null) {
                return;
            }
            float w = get_width ();
            float h = get_height ();
            float scale = float.max (w / texture.width, h / texture.height);
            float dw = texture.width * scale;
            float dh = texture.height * scale;
            var bounds = Graphene.Rect ();
            bounds.init (0, 0, w, h);
            var area = Graphene.Rect ();
            area.init ((w - dw) / 2, (h - dh) / 2, dw, dh);
            snapshot.push_clip (bounds);
            snapshot.append_texture (texture, area);
            snapshot.pop ();
        }
    }
}
