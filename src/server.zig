const std = @import("std");
const Allocator = std.mem.Allocator;
const protocol = @import("protocol.zig");
const schema = @import("schema.zig");

pub const Server = struct {
    allocator: Allocator,
    info: protocol.ServerInfo,
    tools: std.ArrayList(ToolEntry),
    resources: std.ArrayList(ResourceEntry),
    prompts: std.ArrayList(PromptEntry),

    pub const ToolHandlerFn = *const fn (allocator: Allocator, args_json: []const u8) anyerror!protocol.CallToolResult;
    pub const ResourceHandlerFn = *const fn (allocator: Allocator, uri: []const u8) anyerror!protocol.ResourceContents;
    pub const PromptHandlerFn = *const fn (allocator: Allocator, args_json: []const u8) anyerror![]const protocol.PromptMessage;

    pub const ToolEntry = struct {
        name: []const u8,
        description: []const u8,
        schema_json: []const u8,
        handler: ToolHandlerFn,
    };

    pub const ResourceEntry = struct {
        uri: []const u8,
        name: []const u8,
        description: ?[]const u8,
        mime_type: ?[]const u8,
        handler: ResourceHandlerFn,
    };

    pub const PromptEntry = struct {
        name: []const u8,
        description: ?[]const u8,
        arguments: []const protocol.PromptArgument,
        handler: PromptHandlerFn,
    };

    pub fn init(allocator: Allocator, info: protocol.ServerInfo) Server {
        return .{
            .allocator = allocator,
            .info = info,
            .tools = .empty,
            .resources = .empty,
            .prompts = .empty,
        };
    }

    pub fn deinit(self: *Server) void {
        self.tools.deinit(self.allocator);
        self.resources.deinit(self.allocator);
        self.prompts.deinit(self.allocator);
    }

    /// Registers a strongly-typed tool with automated schema synthesis
    pub fn registerTool(self: *Server, comptime Tool: type) !void {
        const tool_name = if (@hasDecl(Tool, "name")) Tool.name else @typeName(Tool);
        const tool_desc = if (@hasDecl(Tool, "description")) Tool.description else "";

        const ParamsType = if (@hasDecl(Tool, "Params")) Tool.Params else struct {};
        const schema_json = schema.generateSchemaJson(ParamsType);

        const wrapper = struct {
            fn handle(alloc: Allocator, args_json: []const u8) anyerror!protocol.CallToolResult {
                var params: ParamsType = undefined;
                if (@sizeOf(ParamsType) > 0) {
                    const trimmed = std.mem.trim(u8, args_json, " \t\r\n");
                    var parsed = std.json.parseFromSlice(
                        ParamsType,
                        alloc,
                        trimmed,
                        .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
                    ) catch |err| {
                        var err_buf: [256]u8 = undefined;
                        const err_msg = try std.fmt.bufPrint(&err_buf, "Failed to parse arguments: {s}", .{@errorName(err)});
                        return protocol.CallToolResult.err(err_msg);
                    };
                    defer parsed.deinit();
                    params = parsed.value;

                    if (@hasDecl(Tool, "call")) {
                        return Tool.call(params, alloc);
                    } else if (@hasDecl(Tool, "execute")) {
                        return Tool.execute(params, alloc);
                    } else {
                        return protocol.CallToolResult.err("Tool implementation missing call/execute function");
                    }
                } else {
                    params = .{};
                    if (@hasDecl(Tool, "call")) {
                        return Tool.call(params, alloc);
                    } else if (@hasDecl(Tool, "execute")) {
                        return Tool.execute(params, alloc);
                    } else {
                        return protocol.CallToolResult.err("Tool implementation missing call/execute function");
                    }
                }
            }
        };

        try self.tools.append(self.allocator, .{
            .name = tool_name,
            .description = tool_desc,
            .schema_json = schema_json,
            .handler = wrapper.handle,
        });
    }

    /// Handles a single incoming JSON-RPC raw message and produces the response JSON (or null for notifications)
    pub fn handleMessage(self: *Server, allocator: Allocator, raw_json: []const u8) !?[]u8 {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        const maybe_resp = try self.dispatchMessage(arena_alloc, raw_json);
        if (maybe_resp) |resp| {
            return try allocator.dupe(u8, resp);
        }
        return null;
    }

    fn dispatchMessage(self: *Server, allocator: Allocator, raw_json: []const u8) !?[]u8 {
        var parsed_json = std.json.parseFromSlice(
            std.json.Value,
            allocator,
            raw_json,
            .{},
        ) catch {
            return try self.formatErrorResponse(allocator, .null_id, .parse_error, "Parse error");
        };
        defer parsed_json.deinit();

        const root = parsed_json.value;
        if (root != .object) {
            return try self.formatErrorResponse(allocator, .null_id, .invalid_request, "Invalid JSON-RPC request");
        }

        const method_val = root.object.get("method") orelse {
            return try self.formatErrorResponse(allocator, .null_id, .invalid_request, "Missing method");
        };
        if (method_val != .string) {
            return try self.formatErrorResponse(allocator, .null_id, .invalid_request, "Method must be a string");
        }
        const method = method_val.string;

        const id_val = root.object.get("id");
        const req_id: ?protocol.RequestId = if (id_val) |id| switch (id) {
            .integer => |i| protocol.RequestId{ .integer = i },
            .string => |s| protocol.RequestId{ .string = s },
            .null => protocol.RequestId.null_id,
            else => protocol.RequestId.null_id,
        } else null;

        const params_val = root.object.get("params");

        // Handle Dispatching
        if (std.mem.eql(u8, method, "initialize")) {
            if (req_id == null) return null; // notification
            return try self.handleInitialize(allocator, req_id.?);
        } else if (std.mem.eql(u8, method, "notifications/initialized") or std.mem.eql(u8, method, "initialized")) {
            // Notification: no response
            return null;
        } else if (std.mem.eql(u8, method, "ping")) {
            if (req_id == null) return null;
            return try self.formatSuccessResponse(allocator, req_id.?, "{}");
        } else if (std.mem.eql(u8, method, "tools/list")) {
            if (req_id == null) return null;
            return try self.handleToolsList(allocator, req_id.?);
        } else if (std.mem.eql(u8, method, "tools/call")) {
            if (req_id == null) return null;
            return try self.handleToolsCall(allocator, req_id.?, params_val);
        } else if (std.mem.eql(u8, method, "resources/list")) {
            if (req_id == null) return null;
            return try self.handleResourcesList(allocator, req_id.?);
        } else if (std.mem.eql(u8, method, "resources/read")) {
            if (req_id == null) return null;
            return try self.handleResourcesRead(allocator, req_id.?, params_val);
        } else if (std.mem.eql(u8, method, "prompts/list")) {
            if (req_id == null) return null;
            return try self.handlePromptsList(allocator, req_id.?);
        } else {
            if (req_id) |rid| {
                return try self.formatErrorResponse(allocator, rid, .method_not_found, "Method not found");
            }
            return null;
        }
    }

    fn handleInitialize(self: *Server, allocator: Allocator, id: protocol.RequestId) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        var writer = BufferWriter{ .list = &buf, .allocator = allocator };
        try writer.writeAll("{\"protocolVersion\":\"");
        try writer.writeAll(protocol.LATEST_PROTOCOL_VERSION);
        try writer.writeAll("\",\"capabilities\":{\"tools\":{\"listChanged\":false},\"resources\":{\"listChanged\":false},\"prompts\":{\"listChanged\":false}},\"serverInfo\":{\"name\":\"");
        try protocol.writeJsonEscaped(&writer, self.info.name);
        try writer.writeAll("\",\"version\":\"");
        try protocol.writeJsonEscaped(&writer, self.info.version);
        try writer.writeByte('"');
        if (self.info.instructions) |inst| {
            try writer.writeAll(",\"instructions\":\"");
            try protocol.writeJsonEscaped(&writer, inst);
            try writer.writeByte('"');
        }
        try writer.writeByte('}');
        try writer.writeByte('}');

        const result_json = buf.toOwnedSlice(allocator) catch unreachable;
        defer allocator.free(result_json);

        return self.formatSuccessResponse(allocator, id, result_json);
    }

    fn handleToolsList(self: *Server, allocator: Allocator, id: protocol.RequestId) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        var writer = BufferWriter{ .list = &buf, .allocator = allocator };
        try writer.writeAll("{\"tools\":[");

        for (self.tools.items, 0..) |tool, idx| {
            if (idx > 0) try writer.writeByte(',');
            try writer.writeAll("{\"name\":\"");
            try protocol.writeJsonEscaped(&writer, tool.name);
            try writer.writeAll("\",\"description\":\"");
            try protocol.writeJsonEscaped(&writer, tool.description);
            try writer.writeAll("\",\"inputSchema\":");
            try writer.writeAll(tool.schema_json);
            try writer.writeByte('}');
        }

        try writer.writeAll("]}");

        const result_json = buf.toOwnedSlice(allocator) catch unreachable;
        defer allocator.free(result_json);

        return self.formatSuccessResponse(allocator, id, result_json);
    }

    fn handleToolsCall(self: *Server, allocator: Allocator, id: protocol.RequestId, params_val: ?std.json.Value) ![]u8 {
        if (params_val == null or params_val.? != .object) {
            return self.formatErrorResponse(allocator, id, .invalid_params, "Expected params object");
        }

        const name_val = params_val.?.object.get("name") orelse {
            return self.formatErrorResponse(allocator, id, .invalid_params, "Missing tool name");
        };
        if (name_val != .string) {
            return self.formatErrorResponse(allocator, id, .invalid_params, "Tool name must be string");
        }
        const tool_name = name_val.string;

        const args_val = params_val.?.object.get("arguments");

        // Format arguments into a JSON string to pass to handler
        var args_json_slice: []const u8 = "{}";
        var allocated_args: ?[]u8 = null;
        defer if (allocated_args) |s| allocator.free(s);

        if (args_val) |av| {
            if (av == .object) {
                allocated_args = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(av, .{})});
                args_json_slice = allocated_args.?;
            }
        }

        // Find matching tool
        for (self.tools.items) |tool| {
            if (std.mem.eql(u8, tool.name, tool_name)) {
                const res = tool.handler(allocator, args_json_slice) catch |err| {
                    var err_buf: [256]u8 = undefined;
                    const err_msg = try std.fmt.bufPrint(&err_buf, "Tool execution failed: {s}", .{@errorName(err)});
                    return self.formatToolCallResult(allocator, id, protocol.CallToolResult.err(err_msg));
                };
                return self.formatToolCallResult(allocator, id, res);
            }
        }

        return self.formatErrorResponse(allocator, id, .tool_not_found, "Tool not found");
    }

    fn handleResourcesList(self: *Server, allocator: Allocator, id: protocol.RequestId) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        var writer = BufferWriter{ .list = &buf, .allocator = allocator };
        try writer.writeAll("{\"resources\":[");

        for (self.resources.items, 0..) |res, idx| {
            if (idx > 0) try writer.writeByte(',');
            try writer.writeAll("{\"uri\":\"");
            try protocol.writeJsonEscaped(&writer, res.uri);
            try writer.writeAll("\",\"name\":\"");
            try protocol.writeJsonEscaped(&writer, res.name);
            try writer.writeByte('"');
            if (res.description) |d| {
                try writer.writeAll(",\"description\":\"");
                try protocol.writeJsonEscaped(&writer, d);
                try writer.writeByte('"');
            }
            if (res.mime_type) |m| {
                try writer.writeAll(",\"mimeType\":\"");
                try protocol.writeJsonEscaped(&writer, m);
                try writer.writeByte('"');
            }
            try writer.writeByte('}');
        }

        try writer.writeAll("]}");

        const result_json = buf.toOwnedSlice(allocator) catch unreachable;
        defer allocator.free(result_json);

        return self.formatSuccessResponse(allocator, id, result_json);
    }

    fn handleResourcesRead(self: *Server, allocator: Allocator, id: protocol.RequestId, params_val: ?std.json.Value) ![]u8 {
        if (params_val == null or params_val.? != .object) {
            return self.formatErrorResponse(allocator, id, .invalid_params, "Expected params object");
        }

        const uri_val = params_val.?.object.get("uri") orelse {
            return self.formatErrorResponse(allocator, id, .invalid_params, "Missing resource uri");
        };
        if (uri_val != .string) {
            return self.formatErrorResponse(allocator, id, .invalid_params, "Resource uri must be string");
        }
        const uri = uri_val.string;

        for (self.resources.items) |res| {
            if (std.mem.eql(u8, res.uri, uri)) {
                const contents = res.handler(allocator, uri) catch |err| {
                    var err_buf: [256]u8 = undefined;
                    const err_msg = try std.fmt.bufPrint(&err_buf, "Resource read failed: {s}", .{@errorName(err)});
                    return self.formatErrorResponse(allocator, id, .internal_error, err_msg);
                };

                var buf: std.ArrayList(u8) = .empty;
                errdefer buf.deinit(allocator);
                var writer = BufferWriter{ .list = &buf, .allocator = allocator };
                try writer.writeAll("{\"contents\":[{\"uri\":\"");
                try protocol.writeJsonEscaped(&writer, contents.uri);
                try writer.writeByte('"');
                if (contents.mimeType) |m| {
                    try writer.writeAll(",\"mimeType\":\"");
                    try protocol.writeJsonEscaped(&writer, m);
                    try writer.writeByte('"');
                }
                if (contents.text) |t| {
                    try writer.writeAll(",\"text\":\"");
                    try protocol.writeJsonEscaped(&writer, t);
                    try writer.writeByte('"');
                }
                try writer.writeAll("}]}");

                const result_json = try buf.toOwnedSlice(allocator);
                defer allocator.free(result_json);
                return self.formatSuccessResponse(allocator, id, result_json);
            }
        }

        return self.formatErrorResponse(allocator, id, .resource_not_found, "Resource not found");
    }

    fn handlePromptsList(self: *Server, allocator: Allocator, id: protocol.RequestId) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        var writer = BufferWriter{ .list = &buf, .allocator = allocator };
        try writer.writeAll("{\"prompts\":[");

        for (self.prompts.items, 0..) |p, idx| {
            if (idx > 0) try writer.writeByte(',');
            try writer.writeAll("{\"name\":\"");
            try protocol.writeJsonEscaped(&writer, p.name);
            try writer.writeByte('"');
            if (p.description) |d| {
                try writer.writeAll(",\"description\":\"");
                try protocol.writeJsonEscaped(&writer, d);
                try writer.writeByte('"');
            }
            try writer.writeAll(",\"arguments\":[");
            for (p.arguments, 0..) |arg, a_idx| {
                if (a_idx > 0) try writer.writeByte(',');
                try writer.writeAll("{\"name\":\"");
                try protocol.writeJsonEscaped(&writer, arg.name);
                try writer.writeByte('"');
                if (arg.description) |ad| {
                    try writer.writeAll(",\"description\":\"");
                    try protocol.writeJsonEscaped(&writer, ad);
                    try writer.writeByte('"');
                }
                try writer.print(",\"required\":{s}}}", .{if (arg.required) "true" else "false"});
            }
            try writer.writeAll("]}");
        }

        try writer.writeAll("]}");

        const result_json = buf.toOwnedSlice(allocator) catch unreachable;
        defer allocator.free(result_json);

        return self.formatSuccessResponse(allocator, id, result_json);
    }

    fn formatToolCallResult(self: *Server, allocator: Allocator, id: protocol.RequestId, result: protocol.CallToolResult) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        var writer = BufferWriter{ .list = &buf, .allocator = allocator };
        try writer.writeAll("{\"content\":[");

        if (result.text_content) |t| {
            try writer.writeAll("{\"type\":\"text\",\"text\":\"");
            try protocol.writeJsonEscaped(&writer, t);
            try writer.writeAll("\"}");
        } else {
            for (result.custom_content, 0..) |item, idx| {
                if (idx > 0) try writer.writeByte(',');
                switch (item) {
                    .text => |t| {
                        try writer.writeAll("{\"type\":\"text\",\"text\":\"");
                        try protocol.writeJsonEscaped(&writer, t);
                        try writer.writeAll("\"}");
                    },
                    .image => |img| {
                        try writer.writeAll("{\"type\":\"image\",\"data\":\"");
                        try protocol.writeJsonEscaped(&writer, img.data);
                        try writer.writeAll("\",\"mimeType\":\"");
                        try protocol.writeJsonEscaped(&writer, img.mimeType);
                        try writer.writeAll("\"}");
                    },
                    .resource => |r| {
                        try writer.writeAll("{\"type\":\"resource\",\"resource\":{\"uri\":\"");
                        try protocol.writeJsonEscaped(&writer, r.uri);
                        try writer.writeByte('"');
                        if (r.text) |t| {
                            try writer.writeAll(",\"text\":\"");
                            try protocol.writeJsonEscaped(&writer, t);
                            try writer.writeByte('"');
                        }
                        try writer.writeAll("}}");
                    },
                }
            }
        }

        try writer.print("],\"isError\":{s}}}", .{if (result.isError) "true" else "false"});

        const res_json = try buf.toOwnedSlice(allocator);
        defer allocator.free(res_json);

        return self.formatSuccessResponse(allocator, id, res_json);
    }

    pub fn formatSuccessResponse(self: *Server, allocator: Allocator, id: protocol.RequestId, result_json: []const u8) ![]u8 {
        _ = self;
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        var writer = BufferWriter{ .list = &buf, .allocator = allocator };
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try id.format(&writer);
        try writer.writeAll(",\"result\":");
        try writer.writeAll(result_json);
        try writer.writeByte('}');

        return buf.toOwnedSlice(allocator);
    }

    pub fn formatErrorResponse(self: *Server, allocator: Allocator, id: protocol.RequestId, code: protocol.ErrorCode, message: []const u8) ![]u8 {
        _ = self;
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        var writer = BufferWriter{ .list = &buf, .allocator = allocator };
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try id.format(&writer);
        try writer.print(",\"error\":{{\"code\":{d},\"message\":\"", .{@intFromEnum(code)});
        try protocol.writeJsonEscaped(&writer, message);
        try writer.writeAll("\"}}");

        return buf.toOwnedSlice(allocator);
    }
};

pub const BufferWriter = struct {
    list: *std.ArrayList(u8),
    allocator: Allocator,

    pub fn writeByte(self: *BufferWriter, byte: u8) !void {
        try self.list.append(self.allocator, byte);
    }

    pub fn writeAll(self: *BufferWriter, bytes: []const u8) !void {
        try self.list.appendSlice(self.allocator, bytes);
    }

    pub fn print(self: *BufferWriter, comptime fmt: []const u8, args: anytype) !void {
        var buf: [512]u8 = undefined;
        const formatted = try std.fmt.bufPrint(&buf, fmt, args);
        try self.writeAll(formatted);
    }
};
