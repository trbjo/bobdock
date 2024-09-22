public class Background : Gtk.Widget {

    private static AppSettings settings;

    static construct {
        settings =  AppSettings.get_default();
    }

    protected class Padding : Gtk.Widget {
        construct {
            css_classes = {"dock-item"};
        }
    }

    public Gtk.Image image_size { get; construct; }
    public Padding padding { get; construct; }

    construct {
        name = "background";
        can_target = false;

        image_size = new Gtk.Image();
        image_size.set_parent(this);

        padding = new Padding();
        padding.set_parent(this);
    }

    public int last_size { get; private set; default = 0; }
    public signal void secondary_size_changed();

    public override void size_allocate(int width, int height, int baseline) {
        base.size_allocate(width, height, baseline);

        int size = settings.edge == GtkLayerShell.Edge.BOTTOM ? height : width;
        if (last_size != size) {
            secondary_size_changed();
            last_size = size;
        }
    }


    public override void snapshot(Gtk.Snapshot snapshot) { }
}
