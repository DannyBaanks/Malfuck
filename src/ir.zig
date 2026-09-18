const std = @import("std");

pub const Op = enum { move_right, move_left, increment, decrement, output, input, jump_zero, jump_nonzero };

pub const Instruction = struct {
    op: Op,
    target: ?usize = null,
    source_pos: usize,
};

pub const Image = struct {
    code: std.ArrayListUnmanaged(Instruction) = .empty,

    pub fn deinit(self: *Image, allocator: std.mem.Allocator) void {
        self.code.deinit(allocator);
    }
};

pub const ParseError = error{ UnmatchedOpen, UnmatchedClose, OutOfMemory };

pub fn parse(source: []const u8, allocator: std.mem.Allocator) ParseError!Image {
    var image = Image{};
    errdefer image.deinit(allocator);
    var stack: std.ArrayListUnmanaged(usize) = .empty;
    defer stack.deinit(allocator);

    for (source, 0..) |ch, source_pos| {
        const op: ?Op = switch (ch) {
            '>' => .move_right,
            '<' => .move_left,
            '+' => .increment,
            '-' => .decrement,
            '.' => .output,
            ',' => .input,
            '[' => .jump_zero,
            ']' => .jump_nonzero,
            else => null,
        };
        if (op == null) continue;
        const index = image.code.items.len;
        try image.code.append(allocator, .{ .op = op.?, .source_pos = source_pos });
        switch (op.?) {
            .jump_zero => try stack.append(allocator, index),
            .jump_nonzero => {
                const open = stack.pop() orelse return error.UnmatchedClose;
                image.code.items[index].target = open;
                image.code.items[open].target = index;
            },
            else => {},
        }
    }
    if (stack.items.len != 0) return error.UnmatchedOpen;
    return image;
}

test "nested loops receive reciprocal targets" {
    var image = try parse(">[+[-].]<", std.testing.allocator);
    defer image.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 9), image.code.items.len);
    try std.testing.expectEqual(@as(usize, 7), image.code.items[1].target.?);
    try std.testing.expectEqual(@as(usize, 5), image.code.items[3].target.?);
}

test "unmatched brackets are rejected" {
    try std.testing.expectError(error.UnmatchedOpen, parse("[+", std.testing.allocator));
    try std.testing.expectError(error.UnmatchedClose, parse("]", std.testing.allocator));
}
