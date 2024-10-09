public class SwayConnector : Object, IDesktopConnector {
    private SwayIPCClient listen_client;
    private SwayIPCClient send_client;
    private HashTable<string, WindowInfo> apps;
    private HashTable<int?, string> container_to_app_id;
    private HashTable<string, int> focused_container_per_app;
    private int? currently_focused_container;

    public signal void selected_container_changed(int cont_id);

    construct {
        apps = new HashTable<string, WindowInfo>(str_hash, str_equal);
        container_to_app_id = new HashTable<int?, string>(int_hash, int_equal);
        focused_container_per_app = new HashTable<string, int>(str_hash, int_equal);
        currently_focused_container = null;

        listen_client = new SwayIPCClient();
        send_client = new SwayIPCClient();
    }

    private async void listen() {
        try {
            while (true) {
                var reply = yield listen_client.receive_message();
                if (reply == null) {
                    debug("Received null reply, exiting");
                    break;
                }

                string message_string = (string)reply;
                var event = listen_client.decode_window_event(message_string);
                if (event != null) {
                    handle_window_event(event);
                } else {
                    debug("Failed to decode event");
                }
            }
        } catch (Error e) {
            error("Error: %s\n", e.message);
        }
    }

    public async void start() {
        try {
            yield listen_client.connect_sway();
            yield send_client.connect_sway();
            listen_client.subscribe_to_window_events.begin((obj, res)=> {
                try {
                    bool subscribed = listen_client.subscribe_to_window_events.end(res);
                    if (!subscribed) {
                        error("Failed to subscribe to window events");
                    }
                    send_client.get_tree.begin((obj, res) => {
                        try {
                            var tree =  send_client.get_tree.end(res);
                            if (tree != null) {
                                add_existing_apps(tree);
                            }
                            listen.begin();
                        } catch (Error e) { }
                    });
                } catch (Error e) { }
            });
        } catch (Error e) {
            error("Error: %s\n", e.message);
        }
    }

    public async void stop() {
        // TODO
    }

    protected WindowInfo? get_or_create_window_item(SwayIPCClient.Application swaywindow) {
        if (apps.contains(swaywindow.app_id)) {
            return apps.get(swaywindow.app_id);
        }
        string name = swaywindow.name ?? "No Window Title";

        string path = Utils.find_desktop_file(swaywindow.app_id, name);
        if (path == null) {
            return null;
        }
        var dai = new DesktopAppInfo.from_filename(path);
        if (dai == null) {
            return null;
        }

        uint hash = AppItem.app_item_hash(dai);
        var winfo = new WindowInfo(hash, swaywindow.app_id, name);
        this.selected_container_changed.connect(winfo.selected_container_changed);
        winfo.app_activated.connect(on_app_activated);
        apps.insert(swaywindow.app_id, winfo);
        return winfo;
    }


    private void on_app_activated(string app_id) {
        var containers = get_containers_for_app(app_id);
        if (containers.length() == 0) {
            return;
        }

        int container_to_focus;
        containers.sort((a, b) => a - b);
        if (focused_container_per_app.contains(app_id) &&
            containers.find(focused_container_per_app[app_id]) != null &&
            currently_focused_container == focused_container_per_app[app_id]) {
            // App is currently focused, cycle to next window
            int current_focus = focused_container_per_app[app_id];
            int index = containers.index(current_focus);
            uint next_index = (index + 1) % containers.length();
            container_to_focus = containers.nth_data(next_index);
        } else {
            // App is not focused or it's the first activation, focus the first window
            container_to_focus = focused_container_per_app[app_id];
            if (container_to_focus == 0) {
                container_to_focus = containers.first().data;
            }
        }
        send_client.focus_window_by_con_id(container_to_focus);
    }

    protected void handle_window_event(SwayIPCClient.WindowEvent event) {
        switch (event.change) {
            case SwayIPCClient.WindowChange.NEW:
                var window_item = get_or_create_window_item(event.container);
                if (window_item != null) {
                    container_to_app_id.insert(event.container.id, event.container.app_id);
                    window_item.add_window(event.container.id);
                    update_apps();
                } else {
                    warning("could not create window_item for app: %s", event.container.app_id);
                }
                break;
            case SwayIPCClient.WindowChange.CLOSE:
                string? app_id = container_to_app_id.get(event.container.id);
                if (app_id == null) {
                    return;
                }
                var window_item = apps.get(app_id);
                window_item.remove_window(event.container.id);
                if (!window_item.has_windows()) {
                    apps.remove(app_id);
                }
                container_to_app_id.remove(event.container.id);
                update_apps();
                break;
            case SwayIPCClient.WindowChange.FOCUS:
                currently_focused_container = event.container.id;
                this.selected_container_changed(event.container.id);

                string? app_id = container_to_app_id.get(event.container.id);
                if (app_id != null) {
                    focused_container_per_app[app_id] = event.container.id;
                    var window_item = apps.get(app_id);
                    if (window_item != null) {
                        window_item.title = event.container.name;
                    }
                }
                break;
            case SwayIPCClient.WindowChange.TITLE:
                string? app_id = container_to_app_id.get(event.container.id);
                if (app_id != null) {
                    var window_item = apps.get(app_id);
                    if (window_item != null) {
                        window_item.title = event.container.name;
                    }
                }
                break;
            case SwayIPCClient.WindowChange.MOVE:
            case SwayIPCClient.WindowChange.FLOATING:
            case SwayIPCClient.WindowChange.FULLSCREEN_MODE:
            case SwayIPCClient.WindowChange.MARK:
            case SwayIPCClient.WindowChange.URGENT:
                break;
        }
        // debug("event.change: %s, app: %s", event.change.to_string(), event.container.app_id);
    }

    private void add_existing_apps(SwayIPCClient.Tree tree) {
        var sway_apps = send_client.get_apps(tree);
        foreach (var app in sway_apps) {
            var window_item = get_or_create_window_item(app);
            if (window_item != null) {
                container_to_app_id.insert(app.id, app.app_id);
                window_item.add_window(app.id);
            }

            if (app.focused) {
                focused_container_per_app[app.app_id] = app.id;
                currently_focused_container = app.id;
                this.selected_container_changed(app.id);
            }
        }
        update_apps();
    }

    private List<int> get_containers_for_app(string app_id) {
        var containers = new List<int>();
        container_to_app_id.foreach((container_id, current_app_id) => {
            if (current_app_id == app_id) {
                containers.append(container_id);
            }
        });
        return (owned) containers;
    }

    protected void update_apps() {
        var app_map = new HashTable<uint?, unowned WindowInfo>(int_hash, int_equal);

        apps.foreach((key, value) => {
            app_map.set(value.hash, value);
        });

        apps_changed(app_map);
    }
}
