public class SwayIPCClient : Object {
    private SocketConnection connection;
    private DataInputStream input_stream;
    private DataOutputStream output_stream;

    private const string MAGIC_STRING = "i3-ipc";
    private const int HEADERLEN = 14; // 6 (magic string) + 4 (payload length) + 4 (message type)

    public enum IPCCommand {
        RUN_COMMAND = 0,
        GET_WORKSPACES = 1,
        SUBSCRIBE = 2,
        GET_OUTPUTS = 3,
        GET_TREE = 4,
        GET_MARKS = 5,
        GET_BAR_CONFIG = 6,
        GET_VERSION = 7,
        GET_BINDING_MODES = 8,
        GET_CONFIG = 9,
        SEND_TICK = 10,
        SYNC = 11,
        GET_INPUTS = 100,
        GET_SEATS = 101
    }

    public async void connect_sway() throws Error {
        var socket_path = get_sway_socket_path();
        debug("Connecting to Sway socket: %s", socket_path);

        var socket_address = new UnixSocketAddress(socket_path);
        var client = new SocketClient();
        connection = yield client.connect_async(socket_address);

        debug("Connected to Sway socket");

        input_stream = new DataInputStream(connection.input_stream);
        output_stream = new DataOutputStream(connection.output_stream);
    }

    private string get_sway_socket_path() throws Error {
        var swaysock = Environment.get_variable("SWAYSOCK");
        if (swaysock != null) {
            return swaysock;
        }
        var i3sock = Environment.get_variable("I3SOCK");
        if (i3sock != null) {
            return i3sock;
        }
        throw new IOError.NOT_FOUND("Could not find Sway or i3 socket path");
    }

    public async bool subscribe_to_window_events() throws Error {
        var subscribe_payload = new Json.Array();
        subscribe_payload.add_string_element("window");

        var generator = new Json.Generator();
        var root = new Json.Node(Json.NodeType.ARRAY);
        root.set_array(subscribe_payload);
        generator.set_root(root);

        var subscribe_message = generator.to_data(null);

        print("Subscribing to window events");
        yield send_message(IPCCommand.SUBSCRIBE, subscribe_message);
        var reply = yield receive_message();

        var parser = new Json.Parser();
        parser.load_from_data((string)reply);
        var reply_object = parser.get_root().get_object();

        bool success = reply_object.get_boolean_member("success");
        debug("Subscription reply: %s", success.to_string());

        return success;
    }

    private async void send_message(IPCCommand command, string payload) throws Error {
        uint8[] header = new uint8[HEADERLEN];
        uint32 length = (uint32)(payload.length);

        Memory.copy(header, MAGIC_STRING.data, 6);
        Memory.copy(&header[6], &length, 4);
        uint32 cmd = (uint32)command;
        Memory.copy(&header[10], &cmd, 4);

        debug("Sending message: type=%d, length=%u", (int)command, length);

        try {
            yield output_stream.write_all_async(header, Priority.DEFAULT, null,null);
            yield output_stream.write_all_async(payload.data, Priority.DEFAULT, null,null);
            yield output_stream.flush_async();
        } catch (Error e) {
            throw new IOError.FAILED("Failed to send message: %s", e.message);
        }
    }

    public async uint8[]? receive_message() throws Error {
        try {
            Bytes header_bytes = yield input_stream.read_bytes_async(HEADERLEN, Priority.DEFAULT);
            if (header_bytes.length < HEADERLEN) {
                throw new IOError.FAILED("Failed to read complete header");
            }

            uint8[] header = header_bytes.get_data();
            if (Memory.cmp(header, MAGIC_STRING.data, 6) != 0) {
                throw new IOError.INVALID_DATA("Invalid magic string in response");
            }

            uint32 length = *((uint32*)(&header[6]));
            uint32 message_type = *((uint32*)(&header[10]));

            debug("Received message header: type=%u, length=%u", message_type, length);

            Bytes payload_bytes = yield input_stream.read_bytes_async(length, Priority.DEFAULT);
            debug("Received payload of length %lu", payload_bytes.length);

            // Create a new array with an extra byte for null termination
            uint8[] payload = new uint8[payload_bytes.length + 1];
            Memory.copy(payload, payload_bytes.get_data(), payload_bytes.length);
            payload[payload_bytes.length] = 0; // Add null terminator

            debug("Added null terminator. New payload length: %lu", payload.length);

            return payload;
        } catch (Error e) {
            throw new IOError.FAILED("Failed to receive message: %s", e.message);
        }
    }


    public async Json.Object? run_command(string command) throws Error {
        yield send_message(IPCCommand.RUN_COMMAND, command);
        var reply = yield receive_message();

        if (reply == null) {
            throw new IOError.FAILED("No response received from Sway");
        }

        // debug("Raw response data (UTF-8): %s", (string)reply);
        var parser = new Json.Parser();
        parser.load_from_data((string)reply);
        var response_array = parser.get_root().get_array();

        return response_array.get_object_element(0);
    }

    public void focus_window_by_con_id(int con_id) {
        run_command.begin("[con_id=%i] focus".printf(con_id), (obj, res) => {
            try {
                var result = run_command.end(res);
                bool success = result.get_boolean_member("success");
                if (!success) {
                    warning("Failed to focus window with container id: %i", con_id);
                }
            } catch (Error e) {
                warning("Error focusing window: %s", e.message);
            }
        });

    }


    public enum WindowChange {
        CLOSE,
        FLOATING,
        FOCUS,
        FULLSCREEN_MODE,
        MARK,
        MOVE,
        NEW,
        TITLE,
        URGENT;

        public static WindowChange from_string(string str) {
            switch (str) {
                case "close": return CLOSE;
                case "floating": return FLOATING;
                case "focus": return FOCUS;
                case "fullscreen_mode": return FULLSCREEN_MODE;
                case "mark": return MARK;
                case "move": return MOVE;
                case "new": return NEW;
                case "title": return TITLE;
                case "urgent": return URGENT;
                default: return TITLE; // Default to TITLE if unknown
            }
        }
    }

    public struct Rect {
        public int x;
        public int y;
        public int width;
        public int height;

        public static Rect from_json(Json.Object obj) {
            return Rect() {
                x = (int)obj.get_int_member("x"),
                y = (int)obj.get_int_member("y"),
                width = (int)obj.get_int_member("width"),
                height = (int)obj.get_int_member("height")
            };
        }
    }

    public struct IdleInhibitors {
        public string user;
        public string application;
    }

    public class Application : Object {
        public int id;
        public string type;
        public string orientation;
        public double percent;
        public bool urgent;
        public string[] marks;
        public bool focused;
        public string border;
        public int current_border_width;
        public Rect rect;
        public Rect deco_rect;
        public Rect window_rect;
        public Rect geometry;
        public string layout;
        public string? name;
        public int fullscreen_mode;
        public bool sticky;
        public int pid;
        public string app_id;
        public bool visible;
        public int max_render_time;
        public string shell;
        public bool inhibit_idle;
        public IdleInhibitors idle_inhibitors;

        public static Application from_json(Json.Object obj) {
            var app = new Application();

            app.id = (int)obj.get_int_member("id");
            app.type = obj.get_string_member("type");
            app.orientation = obj.get_string_member("orientation");
            app.percent = obj.get_double_member("percent");
            app.urgent = obj.get_boolean_member("urgent");
            app.focused = obj.get_boolean_member("focused");
            app.border = obj.get_string_member("border");
            app.current_border_width = (int)obj.get_int_member("current_border_width");
            app.layout = obj.get_string_member("layout");
            app.name = obj.get_string_member("name");
            app.fullscreen_mode = (int)obj.get_int_member("fullscreen_mode");
            app.sticky = obj.get_boolean_member("sticky");
            app.pid = (int)obj.get_int_member("pid");
            app.app_id = obj.get_string_member("app_id");
            app.visible = obj.get_boolean_member("visible");
            app.max_render_time = (int)obj.get_int_member("max_render_time");
            app.shell = obj.get_string_member("shell");
            app.inhibit_idle = obj.get_boolean_member("inhibit_idle");

            var marks_array = obj.get_array_member("marks");
            app.marks = new string[marks_array.get_length()];
            for (int i = 0; i < marks_array.get_length(); i++) {
                app.marks[i] = marks_array.get_string_element(i);
            }

            app.rect = Rect.from_json(obj.get_object_member("rect"));
            app.deco_rect = Rect.from_json(obj.get_object_member("deco_rect"));
            app.window_rect = Rect.from_json(obj.get_object_member("window_rect"));
            app.geometry = Rect.from_json(obj.get_object_member("geometry"));

            var idle_inhibitors_obj = obj.get_object_member("idle_inhibitors");
            app.idle_inhibitors = IdleInhibitors() {
                user = idle_inhibitors_obj.get_string_member("user"),
                application = idle_inhibitors_obj.get_string_member("application")
            };

            return app;
        }


    }

    public struct WindowEvent {
        public WindowChange change;
        public Application container;
    }


    public class Mode : Object {
        public int height;
        public string picture_aspect_ratio;
        public int refresh;
        public int width;

        public static Mode from_json(Json.Object obj) {
            var mode = new Mode();
            mode.height = (int)obj.get_int_member("height");
            mode.picture_aspect_ratio = obj.get_string_member("picture_aspect_ratio");
            mode.refresh = (int)obj.get_int_member("refresh");
            mode.width = (int)obj.get_int_member("width");
            return mode;
        }
    }

    public async Tree? get_tree() throws Error {
        yield send_message(IPCCommand.GET_TREE, "");
        var reply = yield receive_message();
        if (reply == null) {
            return null;
        }

        var parser = new Json.Parser();
        parser.load_from_data((string)reply);
        var root = parser.get_root();

        return Tree.from_json(root);
    }

    public class Tree : Object {
        public int id;
        public string name;
        public Rect rect;
        public bool focused;
        public int[] focus;
        public string border;
        public int current_border_width;
        public string layout;
        public string orientation;
        public double percent;
        public Rect window_rect;
        public Rect deco_rect;
        public Rect geometry;
        public Json.Node? window;
        public bool urgent;
        // public SwayNode[] floating_nodes;
        public bool sticky;
        public string type;
        public Output[] nodes;

        public static Tree from_json(Json.Node json_node) {
            var obj = json_node.get_object();
            var tree = new Tree();

            tree.id = (int)obj.get_int_member("id");
            tree.name = obj.get_string_member("name");
            tree.rect = Rect.from_json(obj.get_object_member("rect"));
            tree.focused = obj.get_boolean_member("focused");
            tree.focus = json_array_to_int_array(obj.get_array_member("focus"));
            tree.border = obj.get_string_member("border");
            tree.current_border_width = (int)obj.get_int_member("current_border_width");
            tree.layout = obj.get_string_member("layout");
            tree.orientation = obj.get_string_member("orientation");
            tree.percent = obj.get_double_member("percent");
            tree.window_rect = Rect.from_json(obj.get_object_member("window_rect"));
            tree.deco_rect = Rect.from_json(obj.get_object_member("deco_rect"));
            tree.geometry = Rect.from_json(obj.get_object_member("geometry"));
            tree.window = obj.has_member("window") ? obj.get_member("window") : null;
            tree.urgent = obj.get_boolean_member("urgent");
            // tree.floating_nodes = json_array_to_node_array(obj.get_array_member("floating_nodes"));
            tree.sticky = obj.get_boolean_member("sticky");
            tree.type = obj.get_string_member("type");
            tree.nodes = json_array_to_output_array(obj.get_array_member("nodes"));

            return tree;
        }

        private static int[] json_array_to_int_array(Json.Array array) {
            int[] result = new int[array.get_length()];
            for (int i = 0; i < array.get_length(); i++) {
                result[i] = (int)array.get_int_element(i);
            }
            return result;
        }

        private static Output[] json_array_to_output_array(Json.Array array) {
            var result = new GLib.List<Output>();
            for (int i = 0; i < array.get_length(); i++) {
                var element = array.get_element(i);
                if (element.get_node_type() != Json.NodeType.OBJECT) {
                    debug("Skipping non-object node at index %d", i);
                    continue;
                }

                var obj = element.get_object();
                if (!obj.has_member("name")) {
                    debug("Skipping node without 'name' at index %d", i);
                    continue;
                }

                string name = obj.get_string_member("name");
                if (name == "__i3") {
                    debug("Skipping scratchpad output '__i3'");
                    continue;
                }

                var output = Output.from_json(element);
                if (output != null) {
                    result.append(output);
                }
            }

            Output[] array_result = new Output[result.length()];
            for (int i = 0; i < result.length(); i++) {
                array_result[i] = result.nth_data(i);
            }

            return array_result;
        }
    }


    public class Output : Object {
        public bool active;
        public string adaptive_sync_status;
        public bool dpms;
        public string border;
        public string current_workspace;
        public int[] focus;
        public bool focused;
        public int fullscreen_mode;
        public Rect geometry;
        public int id;
        public string layout;
        public int max_render_time;
        public string make;
        public string[] marks;
        public string model;
        public Mode[] modes;
        public string name;
        public Workspace[] nodes;
        public bool non_desktop;
        public bool power;
        public string orientation;
        public bool primary;
        public Rect rect;
        public string serial;
        public float scale;
        public bool sticky;
        public string transform;
        public string type;
        public bool urgent;
        public Rect window_rect;

        public static Output from_json(Json.Node json_node) {
            debug("Entering Output.from_json");
            if (json_node.get_node_type() != Json.NodeType.OBJECT) {
                debug("Error: Expected object for Output, but got %s", json_node.type_name());
            }

            var obj = json_node.get_object();
            var output = new Output();

            // debug("Parsing Output object. Available members:");
            // foreach (var member in obj.get_members()) {
                // debug(" - %s", member);
            // }

            if (obj.has_member("active")) {
                output.active = obj.get_boolean_member("active");
                debug("Parsed active: %s", output.active.to_string());
            } else {
                debug("Warning: 'active' member not found in Output object");
            }

            if (obj.has_member("adaptive_sync_status")) {
                output.adaptive_sync_status = obj.get_string_member("adaptive_sync_status");
                debug("Parsed adaptive_sync_status: %s", output.adaptive_sync_status);
            } else {
                debug("Warning: 'adaptive_sync_status' member not found in Output object");
            }

            output.dpms = obj.get_boolean_member("dpms");
            output.border = obj.get_string_member("border");
            output.current_workspace = obj.get_string_member("current_workspace");
            output.focus = json_array_to_int_array(obj.get_array_member("focus"));
            output.focused = obj.get_boolean_member("focused");
            output.fullscreen_mode = (int)obj.get_int_member("fullscreen_mode");
            output.geometry = Rect.from_json(obj.get_object_member("geometry"));
            output.id = (int)obj.get_int_member("id");
            output.layout = obj.get_string_member("layout");
            output.max_render_time = (int)obj.get_int_member("max_render_time");
            output.make = obj.get_string_member("make");
            output.marks = json_array_to_string_array(obj.get_array_member("marks"));
            output.model = obj.get_string_member("model");
            output.modes = json_array_to_mode_array(obj.get_array_member("modes"));
            output.name = obj.get_string_member("name");
            output.nodes = json_array_to_workspace_array(obj.get_array_member("nodes"));
            output.non_desktop = obj.get_boolean_member("non_desktop");
            output.power = obj.get_boolean_member("power");
            output.orientation = obj.get_string_member("orientation");
            output.primary = obj.get_boolean_member("primary");
            output.rect = Rect.from_json(obj.get_object_member("rect"));
            output.serial = obj.get_string_member("serial");
            output.scale = (float)obj.get_double_member("scale");
            output.sticky = obj.get_boolean_member("sticky");
            output.transform = obj.get_string_member("transform");
            output.type = obj.get_string_member("type");
            output.urgent = obj.get_boolean_member("urgent");
            output.window_rect = Rect.from_json(obj.get_object_member("window_rect"));

            return output;
        }

        private static int[] json_array_to_int_array(Json.Array array) {
            int[] result = new int[array.get_length()];
            for (int i = 0; i < array.get_length(); i++) {
                result[i] = (int)array.get_int_element(i);
            }
            return result;
        }

        private static string[] json_array_to_string_array(Json.Array array) {
            string[] result = new string[array.get_length()];
            for (int i = 0; i < array.get_length(); i++) {
                result[i] = array.get_string_element(i);
            }
            return result;
        }

        private static Mode[] json_array_to_mode_array(Json.Array array) {
            Mode[] result = new Mode[array.get_length()];
            for (int i = 0; i < array.get_length(); i++) {
                result[i] = Mode.from_json(array.get_object_element(i));
            }
            return result;
        }

        private static Workspace[] json_array_to_workspace_array(Json.Array array) {
            Workspace[] result = new Workspace[array.get_length()];
            for (int i = 0; i < array.get_length(); i++) {
                result[i] = Workspace.from_json(array.get_object_element(i));
            }
            return result;
        }
    }


    public class Workspace : Object {
        public string border;
        public int current_border_width;
        public Rect deco_rect;
        public SwayNode[] floating_nodes;
        public int[] focus;
        public bool focused;
        public int fullscreen_mode;
        public Rect geometry;
        public int id;
        public string layout;
        public string[] marks;
        public string name;
        public SwayNode[] nodes;
        public int num;
        public string orientation;
        public string output;
        public Rect rect;
        public string representation;
        public bool sticky;
        public string type;
        public bool urgent;
        public Rect window_rect;

        public static Workspace from_json(Json.Object obj) {
            var workspace = new Workspace();
            workspace.border = obj.get_string_member("border");
            workspace.current_border_width = (int)obj.get_int_member("current_border_width");
            workspace.deco_rect = Rect.from_json(obj.get_object_member("deco_rect"));
            workspace.floating_nodes = json_array_to_node_array(obj.get_array_member("floating_nodes"));
            workspace.focus = json_array_to_int_array(obj.get_array_member("focus"));
            workspace.focused = obj.get_boolean_member("focused");
            workspace.fullscreen_mode = (int)obj.get_int_member("fullscreen_mode");
            workspace.geometry = Rect.from_json(obj.get_object_member("geometry"));
            workspace.id = (int)obj.get_int_member("id");
            workspace.layout = obj.get_string_member("layout");
            workspace.marks = json_array_to_string_array(obj.get_array_member("marks"));
            workspace.name = obj.get_string_member("name");
            workspace.nodes = json_array_to_node_array(obj.get_array_member("nodes"));
            workspace.num = (int)obj.get_int_member("num");
            workspace.orientation = obj.get_string_member("orientation");
            workspace.output = obj.get_string_member("output");
            workspace.rect = Rect.from_json(obj.get_object_member("rect"));
            workspace.representation = obj.get_string_member("representation");
            workspace.sticky = obj.get_boolean_member("sticky");
            workspace.type = obj.get_string_member("type");
            workspace.urgent = obj.get_boolean_member("urgent");
            workspace.window_rect = Rect.from_json(obj.get_object_member("window_rect"));
            return workspace;
        }

        private static SwayNode[] json_array_to_node_array(Json.Array array) {
            SwayNode[] result = new SwayNode[array.get_length()];
            for (int i = 0; i < array.get_length(); i++) {
                result[i] = SwayNode.from_json(array.get_element(i));
            }
            return result;
        }

        private static int[] json_array_to_int_array(Json.Array array) {
            int[] result = new int[array.get_length()];
            for (int i = 0; i < array.get_length(); i++) {
                result[i] = (int)array.get_int_element(i);
            }
            return result;
        }

        private static string[] json_array_to_string_array(Json.Array array) {
            string[] result = new string[array.get_length()];
            for (int i = 0; i < array.get_length(); i++) {
                result[i] = array.get_string_element(i);
            }
            return result;
        }
    }

    public class SwayNode : Object {
        public Application? application;
        public Container? container;

        public static SwayNode from_json(Json.Node json_node) {
            var node = new SwayNode();
            var obj = json_node.get_object();

            if (obj.has_member("app_id")) {
                node.application = Application.from_json(obj);
            } else {
                node.container = Container.from_json(json_node);
            }

            return node;
        }
    }


    public WindowEvent? decode_window_event(string json_string) {
        try {
            var parser = new Json.Parser();
            parser.load_from_data(json_string);
            var root = parser.get_root().get_object();

            var event = WindowEvent();

            event.change = WindowChange.from_string(root.get_string_member("change"));

            var container = root.get_object_member("container");
            event.container = Application.from_json(container);

            return event;
        } catch (Error e) {
            debug("Error decoding window event: %s, json_string: %s", e.message, json_string);
            return null;
        }
    }



    public class Container : Object {
        public string orientation;
        public SwayNode[] floating_nodes;
        public SwayNode[] nodes;

        public static Container from_json(Json.Node json_node) {
            var obj = json_node.get_object();
            var container = new Container();

            container.orientation = obj.get_string_member("orientation");

            var floating_nodes_array = obj.get_array_member("floating_nodes");
            container.floating_nodes = new SwayNode[floating_nodes_array.get_length()];
            for (int i = 0; i < floating_nodes_array.get_length(); i++) {
                container.floating_nodes[i] = SwayNode.from_json(floating_nodes_array.get_element(i));
            }

            var nodes_array = obj.get_array_member("nodes");
            container.nodes = new SwayNode[nodes_array.get_length()];
            for (int i = 0; i < nodes_array.get_length(); i++) {
                container.nodes[i] = SwayNode.from_json(nodes_array.get_element(i));
            }

            return container;
        }
    }

    public GLib.List<Application> get_apps(Tree tree) {
        GLib.List<Application> apps = new GLib.List<Application>();
        foreach (var output in tree.nodes) {
            foreach (var workspace in output.nodes) {
                foreach (var cont in workspace.nodes) {
                    apps.concat(rec_parse_nodes(cont));
                }
                foreach (var cont in workspace.floating_nodes) {
                    apps.concat(rec_parse_nodes(cont));
                }
            }
        }
        return apps;
    }

    private GLib.List<Application> rec_parse_nodes(SwayNode node) {
        GLib.List<Application> results = new GLib.List<Application>();
        if (node.container != null) {
            foreach (var child in node.container.floating_nodes) {
                results.concat(rec_parse_nodes(child));
            }
            foreach (var child in node.container.nodes) {
                results.concat(rec_parse_nodes(child));
            }
        } else if (node.application != null) {
            results.append(node.application);
        }
        return results;
    }
}
