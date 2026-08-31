const std = @import("std");
const Allocator = std.mem.Allocator;

pub const LATEST_PROTOCOL_VERSION = "2024-11-05";

pub const RequestId = union(enum) {
    integer: i64,
    string: []const u8,
    null_id: void,

    pub fn format(self: RequestId, writer: anytype) !void {
        switch (self) {
            .integer => |v| try writer.print("{d}", .{v}),
            .string => |v| {
                try writer.writeByte('"');
                try writeJsonEscaped(writer, v);
                try writer.writeByte('"');
            },
            .null_id => try writer.writeAll("null"),
        }
    }
};

pub const ErrorCode = enum(i32) {
    parse_error = -32700,
    invalid_request = -32600,
    method_not_found = -32601,
    invalid_params = -32602,
    internal_error = -32603,
    resource_not_found = -32002,
    tool_not_found = -32001,
    custom = -32000,
};

pub const TextContent = struct {
    type: []const u8 = "text",
    text: []const u8,
};

pub const ImageContent = struct {
    type: []const u8 = "image",
    data: []const u8,
    mimeType: []const u8,
};

pub const ResourceContents = struct {
    uri: []const u8,
    mimeType: ?[]const u8 = null,
    text: ?[]const u8 = null,
    blob: ?[]const u8 = null,
};

pub const ContentItem = union(enum) {
    text: []const u8,
    image: struct { data: []const u8, mimeType: []const u8 },
    resource: ResourceContents,
};

pub const CallToolResult = struct {
    text_content: ?[]const u8 = null,
    custom_content: []const ContentItem = &.{},
    isError: bool = false,

    pub fn text(t: []const u8) CallToolResult {
        return .{
            .text_content = t,
            .isError = false,
        };
    }

    pub fn err(msg: []const u8) CallToolResult {
        return .{
            .text_content = msg,
            .isError = true,
        };
    }
};

pub const ToolDefinition = struct {
    name: []const u8,
    description: []const u8,
    input_schema_json: []const u8,
};

pub const ResourceDefinition = struct {
    uri: []const u8,
    name: []const u8,
    description: ?[]const u8 = null,
    mime_type: ?[]const u8 = null,
};

pub const PromptArgument = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    required: bool = false,
};

pub const PromptDefinition = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    arguments: []const PromptArgument = &.{},
};

pub const PromptMessage = struct {
    role: enum { user, assistant },
    content: []const u8,
};

pub const ServerInfo = struct {
    name: []const u8,
    version: []const u8,
    instructions: ?[]const u8 = null,
};

pub fn writeJsonEscaped(writer: anytype, str: []const u8) !void {
    for (str) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x08 => try writer.writeAll("\\b"),
            0x0C => try writer.writeAll("\\f"),
            0x00...0x07, 0x0B, 0x0E...0x1F => try writer.print("\\u{x:0>4}", .{c}),
            else => try writer.writeByte(c),
        }
    }
}
