public interface IDesktopConnector : Object {
    public signal void apps_changed(GLib.HashTable<uint?, unowned WindowInfo> sorted_apps);
    public abstract async void start();
    public abstract async void stop();
}

public interface IDockClick {
    public abstract bool handle_click(int n_press);
}

public interface IDockWidget {
    public abstract void set_state_flags(Gtk.StateFlags flags, bool clear);
    public abstract void set_parent(Gtk.Widget parent);
    public abstract void unparent();
    public abstract void size_allocate(int width, int height, int baseline);
    public abstract void snapshot(Gtk.Snapshot snapshot);
}

public interface WidgetHandler : GLib.Object {
    public abstract bool handle_dropped_item(Item file);
    public abstract bool handles_widget(Item file);
}

public interface IUserItem : GLib.Object {
    public abstract string user_id { get; construct; }
}


