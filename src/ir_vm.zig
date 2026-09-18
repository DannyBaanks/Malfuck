const std = @import("std");
const ir = @import("ir.zig");

pub const TapeSize: usize = 30_000;

pub const Result = struct {
    output: []u8,
    steps: u64,
    pointer: usize,

    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        allocator.free(self.output);
    }
};

pub const Error = error{
    StepLimit,
    TapeUnderflow,
    TapeOverflow,
};

pub fn run(image: *const ir.Image, input: []const u8, allocator: std.mem.Allocator, max_steps: u64) !Result {
    var tape: [TapeSize]u8 = .{0} ** TapeSize;
    var output: std.ArrayListUnmanaged(u8) = .empty;
    errdefer output.deinit(allocator);
    var pointer: usize = 0;
    var pc: usize = 0;
    var input_pos: usize = 0;
    var steps: u64 = 0;

    while (pc < image.code.items.len) {
        if (steps >= max_steps) return error.StepLimit;
        steps += 1;
        const instruction = image.code.items[pc];
        switch (instruction.op) {
            .move_right => {
                if (pointer + 1 >= TapeSize) return error.TapeOverflow;
                pointer += 1;
            },
            .move_left => {
                if (pointer == 0) return error.TapeUnderflow;
                pointer -= 1;
            },
            .increment => tape[pointer] +%= 1,
            .decrement => tape[pointer] -%= 1,
            .output => try output.append(allocator, tape[pointer]),
            .input => {
                if (input_pos < input.len) {
                    tape[pointer] = input[input_pos];
                    input_pos += 1;
                } else {
                    tape[pointer] = 0;
                }
            },
            .jump_zero => {
                if (tape[pointer] == 0) pc = instruction.target orelse unreachable;
            },
            .jump_nonzero => {
                if (tape[pointer] != 0) pc = instruction.target orelse unreachable;
            },
        }
        pc += 1;
    }
    return .{ .output = try output.toOwnedSlice(allocator), .steps = steps, .pointer = pointer };
}

test "IR VM executes loop and input" {
    const allocator = std.testing.allocator;
    var image = try ir.parse(",[.,]", allocator);
    defer image.deinit(allocator);
    var result = try run(&image, "ABC", allocator, 100);
    defer result.deinit(allocator);
    try std.testing.expectEqualStrings("ABC", result.output);
}

test "IR VM enforces step limit" {
    const allocator = std.testing.allocator;
    var image = try ir.parse("+[+]", allocator);
    defer image.deinit(allocator);
    try std.testing.expectError(error.StepLimit, run(&image, "", allocator, 10));
}
