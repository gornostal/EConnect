/*
 * SPDX-License-Identifier: MIT
 *
 * Keeps its child at most `maximum_width` wide and centers it, so the page
 * reads as one column on wide windows.
 */
namespace EConnect.App {

    public class Clamp : Gtk.Widget {
        public int maximum_width { get; construct; default = 740; }

        private Gtk.Widget? _child = null;
        public Gtk.Widget? child {
            get { return _child; }
            set {
                if (_child != null) {
                    _child.unparent ();
                }
                _child = value;
                if (_child != null) {
                    _child.set_parent (this);
                }
            }
        }

        public Clamp (int maximum_width) {
            Object (maximum_width: maximum_width);
        }

        public override void dispose () {
            child = null;
            base.dispose ();
        }

        public override Gtk.SizeRequestMode get_request_mode () {
            return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH;
        }

        private int clamp_width (int width) {
            int min, nat, min_base, nat_base;
            _child.measure (Gtk.Orientation.HORIZONTAL, -1, out min, out nat, out min_base, out nat_base);
            return int.max (min, int.min (width, maximum_width));
        }

        public override void measure (Gtk.Orientation orientation, int for_size,
                                      out int minimum, out int natural,
                                      out int minimum_baseline, out int natural_baseline) {
            minimum = natural = 0;
            minimum_baseline = natural_baseline = -1;
            if (_child == null) {
                return;
            }
            if (orientation == Gtk.Orientation.HORIZONTAL) {
                _child.measure (orientation, for_size, out minimum, out natural,
                                out minimum_baseline, out natural_baseline);
                natural = int.max (minimum, int.min (natural, maximum_width));
            } else {
                int width = for_size < 0 ? -1 : clamp_width (for_size);
                _child.measure (orientation, width, out minimum, out natural,
                                out minimum_baseline, out natural_baseline);
            }
        }

        public override void size_allocate (int width, int height, int baseline) {
            if (_child == null) {
                return;
            }
            int child_width = clamp_width (width);
            var point = Graphene.Point () { x = (width - child_width) / 2, y = 0 };
            _child.allocate (child_width, height, baseline, new Gsk.Transform ().translate (point));
        }
    }
}
