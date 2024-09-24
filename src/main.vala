const string BOBDOCK_APP_ID = "io.github.trbjo.bobdock";
const string BOBDOCK_OBJECT_PATH = "/io/github/trbjo/bobdock";

public enum DesktopEnvironment {
    SWAY,
    GNOME,
    KDE,
    UNKNOWN
}

public class DesktopDetector {
    public static DesktopEnvironment detect() {
        // Mock implementation - always returns Sway for now
        return DesktopEnvironment.SWAY;
    }
}

[DBus(name = "io.github.trbjo.bobdock")]
public class DockApp : Gtk.Application {
    private DockWindow window;
    private IDesktopConnector connector;

    public DockApp() {
        Object(application_id: BOBDOCK_APP_ID, flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    [DBus(name = "AutoHide")]
    public void auto_hide() throws Error {
        window.toggle_auto_hide();
    }

    protected override void activate() {
        var desktop_env = DesktopDetector.detect();
        connector = create_connector(desktop_env);

        window = new DockWindow(this, connector);
        window.present();

        connector.start.begin();
    }

    private IDesktopConnector create_connector(DesktopEnvironment env) {
        switch (env) {
            case DesktopEnvironment.SWAY:
                return new SwayConnector();
            case DesktopEnvironment.GNOME:
                error("GNOME connector not implemented");
            case DesktopEnvironment.KDE:
                error("KDE connector not implemented");
            default:
                error("Unknown desktop environment");
        }
    }

    public override bool dbus_register(DBusConnection connection, string object_path) throws Error {
        try {
            connection.register_object(object_path, this);
        } catch (IOError e) {
            error("Could not register object: %s", e.message);
        }
        return true;
    }
}

public static int main(string[] args) {
    return new DockApp().run(args);
}
