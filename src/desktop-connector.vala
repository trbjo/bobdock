public interface IDesktopConnector : Object {
    public signal void apps_changed(GLib.HashTable<uint?, unowned WindowItem> sorted_apps);
    public abstract async void start();
    public abstract async void stop();
}
