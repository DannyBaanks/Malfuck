// conveyor.zig — Autobolge 2.0 Constructive Conveyor Synthesizer (Zig 0.16)
//
// Synthesizes self-contained Classic Malbolge (3^10) programs in O(N) algebraic time
// with ZERO brute-force search.
//
// Architecture (Conveyor Synthesis):
// 1. High-Memory Quantum Jump:
//    Jump c=0 -> 98 -> 99..107 computing target 3312 via
//    crazy(rot^2(80), 72) = 3312, landing on c=3315 with d=121.
// 2. Conveyor Invariant (Delta c == Delta d):
//    - Code segment: c >= 3315
//    - Data segment: d >= 121
//    - Sterile gap: 3,194 cells (C_START - D_START)
// 3. Constructive Emission Matrix:
//    - rot: ('* <', V1)
//    - rot_crazy: ('* p <', V1, V2)
//    - rot_crazy_crazy: ('* p p <', V1, V2, V3) for '+'
// 4. Clean termination 'v' on exit.

const std = @import("std");
const engine = @import("engine.zig");

pub const MEM_SIZE: usize = 59049;
pub const POW9: u16 = 19683;
pub const C_START: usize = 3315;
pub const D_START: usize = 121;
pub const STERILE_GAP: usize = C_START - D_START; // 3194 cells

pub const XLAT1 = "+b(29e*j1VMEKLyC})8&m#~W>qxdRp0wkrUo[D7,XTcA\"lI.v%{gJh4G\\-=O@5`_3i<?Z';FNQuY]szf$!BS/|t:Pn6^Ha";

pub const RecipeKind = enum {
    rot,
    rot_crazy,
    rot_crazy_crazy,
};

pub const Recipe = struct {
    kind: RecipeKind,
    v1: u8,
    v2: u8 = 0,
    v3: u8 = 0,
};

var recipes_initialized: bool = false;
var recipes_table: [256]?Recipe = [_]?Recipe{null} ** 256;

pub fn rotOp(x: u16) u16 {
    return (x / 3) + (x % 3) * POW9;
}

pub fn charFor(op_char: u8, c: usize) u8 {
    const idx_usize = std.mem.indexOfScalar(u8, XLAT1, op_char) orelse 0;
    const idx: i32 = @intCast(idx_usize);
    const c_mod: i32 = @intCast(c % 94);
    const diff: i32 = @mod(idx - c_mod + 94, 94);
    return @intCast(diff + 33);
}

pub fn initRecipes() void {
    if (recipes_initialized) return;

    recipes_table[10] = Recipe{ .kind = .rot, .v1 = 118 }; // '\n'
    recipes_table[43] = Recipe{ .kind = .rot_crazy_crazy, .v1 = 33, .v2 = 54, .v3 = 60 }; // '+'

    var v1: u16 = 33;
    while (v1 < 127) : (v1 += 1) {
        const r1 = rotOp(v1);
        const b1: u8 = @intCast(r1 % 256);
        if (recipes_table[b1] == null) {
            recipes_table[b1] = Recipe{ .kind = .rot, .v1 = @intCast(v1) };
        }
        var v2: u16 = 33;
        while (v2 < 127) : (v2 += 1) {
            const b2: u8 = @intCast(engine.crazyOp(r1, v2) % 256);
            if (recipes_table[b2] == null) {
                recipes_table[b2] = Recipe{ .kind = .rot_crazy, .v1 = @intCast(v1), .v2 = @intCast(v2) };
            }
        }
    }
    recipes_initialized = true;
}

pub fn canFit(target: []const u8) bool {
    initRecipes();
    var data_count: usize = 0;
    for (target) |b| {
        const rec = recipes_table[b] orelse return false;
        switch (rec.kind) {
            .rot => data_count += 2,
            .rot_crazy => data_count += 3,
            .rot_crazy_crazy => data_count += 4,
        }
    }
    return (D_START + data_count) <= C_START;
}

pub fn capacity() usize {
    return STERILE_GAP;
}

pub const ConveyorError = error{
    TargetTooLongForConveyor,
    ByteNotSupported,
    ProgramTooLong,
};

pub fn synthesize(target: []const u8, allocator: std.mem.Allocator) ![]u8 {
    initRecipes();

    var code_ops = std.array_list.Managed(u8).init(allocator);
    defer code_ops.deinit();
    var data_bytes = std.array_list.Managed(u8).init(allocator);
    defer data_bytes.deinit();

    for (target) |b| {
        const rec = recipes_table[b] orelse return ConveyorError.ByteNotSupported;
        switch (rec.kind) {
            .rot => {
                try code_ops.appendSlice(&[_]u8{ '*', '<' });
                try data_bytes.appendSlice(&[_]u8{ rec.v1, 'o' });
            },
            .rot_crazy => {
                try code_ops.appendSlice(&[_]u8{ '*', 'p', '<' });
                try data_bytes.appendSlice(&[_]u8{ rec.v1, rec.v2, 'o' });
            },
            .rot_crazy_crazy => {
                try code_ops.appendSlice(&[_]u8{ '*', 'p', 'p', '<' });
                try data_bytes.appendSlice(&[_]u8{ rec.v1, rec.v2, rec.v3, 'o' });
            },
        }
    }

    try code_ops.append('v'); // Clean HALT

    const total_len = C_START + code_ops.items.len;
    const data_cells = D_START + data_bytes.items.len;

    if (data_cells > C_START) return ConveyorError.TargetTooLongForConveyor;
    if (total_len > MEM_SIZE) return ConveyorError.ProgramTooLong;

    const prog = try allocator.alloc(u8, total_len);
    @memset(prog, 'o');

    // Portal jump from c=0 -> 98 (landing on 99):
    prog[0] = 'b';
    prog[98] = 'o';

    // Low-memory data pointers:
    prog[1] = 93;
    prog[94] = 'P'; // 80: Y1
    prog[95] = 93;
    prog[96] = 73;
    prog[74] = 'H'; // 72: Y2 (crazy produces 3312)
    prog[75] = 73;
    prog[76] = D_START - 1; // 120: target for j at c=3314 to initialize d=121

    // Discriminator / jump sequence at c=99..107:
    prog[99] = charFor('j', 99);
    prog[100] = charFor('*', 100);
    prog[101] = charFor('j', 101);
    prog[102] = charFor('*', 102);
    prog[103] = charFor('o', 103);
    prog[104] = charFor('j', 104);
    prog[105] = charFor('p', 105);
    prog[106] = charFor('j', 106);
    prog[107] = charFor('i', 107);

    // Cushion and bridge at c=3312..3314:
    prog[3312] = 'o';
    prog[3313] = charFor('o', 3313);
    prog[3314] = charFor('j', 3314);

    // Place data segment:
    for (data_bytes.items, 0..) |db, idx| {
        prog[D_START + idx] = db;
    }

    // Place code segment:
    for (code_ops.items, 0..) |opc, idx| {
        prog[C_START + idx] = charFor(opc, C_START + idx);
    }

    return prog;
}

test "conveyor synthesizes hello world" {
    const alloc = std.testing.allocator;
    const target = "Hello World!\n";
    try std.testing.expect(canFit(target));

    const prog = try synthesize(target, alloc);
    defer alloc.free(prog);

    var memory: [engine.MEM_SIZE]u16 = undefined;
    const result = try engine.runInto(&memory, prog, 1_000_000, alloc);
    defer alloc.free(result.output);

    try std.testing.expectEqualStrings(target, result.output);
    try std.testing.expectEqual(engine.RunStatus.halted, result.status);
}
