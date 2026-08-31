const std = @import("std");

pub const StaticWriter = struct {
    buf: *[16384]u8,
    pos: usize = 0,

    pub fn writeByte(self: *StaticWriter, b: u8) !void {
        if (self.pos >= self.buf.len) return error.NoSpaceLeft;
        self.buf[self.pos] = b;
        self.pos += 1;
    }

    pub fn writeAll(self: *StaticWriter, s: []const u8) !void {
        if (self.pos + s.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.pos .. self.pos + s.len], s);
        self.pos += s.len;
    }

    pub fn print(self: *StaticWriter, comptime fmt: []const u8, args: anytype) !void {
        const formatted = try std.fmt.bufPrint(self.buf[self.pos..], fmt, args);
        self.pos += formatted.len;
    }

    pub fn getWritten(self: *const StaticWriter) []const u8 {
        return self.buf[0..self.pos];
    }
};

/// Synthesizes a valid JSON Schema (Draft-7) string at compile time from any Zig type T.
pub fn generateSchemaJson(comptime T: type) []const u8 {
    const static = struct {
        const schema_str = blk: {
            @setEvalBranchQuota(100_000);
            var raw_buf: [16384]u8 = undefined;
            var writer = StaticWriter{ .buf = &raw_buf };

            writeTypeSchema(&writer, T) catch unreachable;

            const slice = writer.getWritten();
            var final_buf: [slice.len]u8 = undefined;
            @memcpy(&final_buf, slice);
            break :blk final_buf;
        };
    };
    return &static.schema_str;
}

fn writeTypeSchema(writer: anytype, comptime T: type) !void {
    const info = @typeInfo(T);
    switch (info) {
        .@"struct" => |s| {
            try writer.writeAll("{\"type\":\"object\",\"properties\":{");

            const help_map = if (@hasDecl(T, "zmcp") and @hasField(@TypeOf(T.zmcp), "help"))
                T.zmcp.help
            else
                .{};

            var prop_count: usize = 0;
            inline for (s.fields) |field| {
                if (prop_count > 0) try writer.writeByte(',');
                try writer.print("\"{s}\":", .{field.name});

                // Write property schema
                try writePropertySchema(writer, field.type, help_map, field.name);
                prop_count += 1;
            }

            try writer.writeAll("},\"required\":[");

            var req_count: usize = 0;
            inline for (s.fields) |field| {
                const is_optional = @typeInfo(field.type) == .optional;
                const has_default = field.default_value_ptr != null;

                if (!is_optional and !has_default) {
                    if (req_count > 0) try writer.writeByte(',');
                    try writer.print("\"{s}\"", .{field.name});
                    req_count += 1;
                }
            }

            try writer.writeAll("]}");
        },
        else => {
            try writePropertySchema(writer, T, .{}, "");
        },
    }
}

fn writePropertySchema(writer: anytype, comptime FieldType: type, comptime help_map: anytype, comptime field_name: []const u8) !void {
    const info = @typeInfo(FieldType);

    const desc: ?[]const u8 = if (field_name.len > 0 and @hasField(@TypeOf(help_map), field_name))
        @field(help_map, field_name)
    else
        null;

    switch (info) {
        .int => {
            try writer.writeAll("{\"type\":\"integer\"");
            if (desc) |d| try writer.print(",\"description\":\"{s}\"", .{d});
            try writer.writeByte('}');
        },
        .float => {
            try writer.writeAll("{\"type\":\"number\"");
            if (desc) |d| try writer.print(",\"description\":\"{s}\"", .{d});
            try writer.writeByte('}');
        },
        .bool => {
            try writer.writeAll("{\"type\":\"boolean\"");
            if (desc) |d| try writer.print(",\"description\":\"{s}\"", .{d});
            try writer.writeByte('}');
        },
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                try writer.writeAll("{\"type\":\"string\"");
                if (desc) |d| try writer.print(",\"description\":\"{s}\"", .{d});
                try writer.writeByte('}');
            } else if (ptr.size == .slice) {
                try writer.writeAll("{\"type\":\"array\",\"items\":");
                try writePropertySchema(writer, ptr.child, .{}, "");
                if (desc) |d| try writer.print(",\"description\":\"{s}\"", .{d});
                try writer.writeByte('}');
            } else {
                try writer.writeAll("{\"type\":\"string\"}");
            }
        },
        .@"enum" => |e| {
            try writer.writeAll("{\"type\":\"string\",\"enum\":[");
            inline for (e.fields, 0..) |f, i| {
                if (i > 0) try writer.writeByte(',');
                try writer.print("\"{s}\"", .{f.name});
            }
            try writer.writeByte(']');
            if (desc) |d| try writer.print(",\"description\":\"{s}\"", .{d});
            try writer.writeByte('}');
        },
        .optional => |opt| {
            // Optional property unwraps inner type
            try writePropertySchema(writer, opt.child, help_map, field_name);
        },
        .@"struct" => {
            try writeTypeSchema(writer, FieldType);
        },
        else => {
            try writer.writeAll("{\"type\":\"string\"}");
        },
    }
}

test "comptime schema generation" {
    const SimpleConfig = struct {
        query: []const u8,
        limit: u32 = 10,
        verbose: ?bool = null,
        mode: enum { fast, exact },

        pub const zmcp = .{
            .help = .{
                .query = "The search query string",
                .limit = "Maximum results to return",
                .mode = "Search precision mode",
            },
        };
    };

    const s = generateSchemaJson(SimpleConfig);
    const expected = "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"The search query string\"},\"limit\":{\"type\":\"integer\",\"description\":\"Maximum results to return\"},\"verbose\":{\"type\":\"boolean\"},\"mode\":{\"type\":\"string\",\"enum\":[\"fast\",\"exact\"],\"description\":\"Search precision mode\"}},\"required\":[\"query\",\"mode\"]}";

    try std.testing.expectEqualStrings(expected, s);
}
