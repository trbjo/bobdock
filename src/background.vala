public class Background : Gtk.Widget {

    private static AppSettings settings;

    static construct {
        settings =  AppSettings.get_default();
    }

    construct {
        name = "background";
        can_target = false;
        can_focus = false;
    }

    public int last_size {
        get {
            return settings.edge == GtkLayerShell.Edge.BOTTOM ? last_height : last_width;
        }
    }

    private int last_height;
    private int last_width;
    public signal void secondary_size_changed();

    public override void size_allocate(int width, int height, int baseline) {
        base.size_allocate(width, height, baseline);

        int size = settings.edge == GtkLayerShell.Edge.BOTTOM ? height : width;
        if (last_size != size) {
            last_height = height;
            last_width = width;
            secondary_size_changed();
        }
    }

    public override void snapshot(Gtk.Snapshot snapshot) { }

}
