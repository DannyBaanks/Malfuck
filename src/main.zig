// malfuck — Brainfuck -> Malbolge.
//
// Modos:
//   malfuck <program.bf> [output.mal] [input.bin] [--classic]
//       Camino Classic extensional: ejecuta BF (con input) y genera un .mal
//       Classic que reproduce exactamente esa salida. El .mal NO conserva la
//       semantica BF para entradas futuras.
//   malfuck <program.bf> [output.mal] [input.bin] --semantic
//       Camino semantico: BF -> IR -> BFIR1 -> HeLL -> Malbolge Free (width
//       10, fixed). El .mal emitido SI conserva cinta, loops e input de BF, y
//       se ejecuta con el runtime Malbolge Free asistido (TAPE_BASE). La CLI
//       lo compila, lo verifica contra la referencia BFIR1 y reporta.
//
// Por defecto (sin bandera) se usa --classic para no cambiar el contrato ya
// verificado; --semantic es el backend verdadero.

const std = @import("std");
const bf = @import("bf_interpreter.zig");
const generator = @import("generator.zig");
const engine = @import("engine.zig");
const ir = @import("ir.zig");
const ir_vm = @import("ir_vm.zig");
const semantic = @import("semantic.zig");

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, alloc);
    defer args.deinit();
    _ = args.next();
    const program_path = args.next() orelse {
        std.debug.print("usage: malfuck <program.bf> [output.mal] [input.bin] [--semantic|--classic]\n", .{});
        return;
    };
    const output_path = args.next() orelse "out.mal";
    var input_path: ?[]const u8 = null;
    var mode_semantic = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--semantic")) {
            mode_semantic = true;
        } else if (std.mem.eql(u8, arg, "--classic")) {
            mode_semantic = false;
        } else {
            input_path = arg;
        }
    }
    const source = try (std.Io.Dir.cwd()).readFileAlloc(init.io, program_path, alloc, .unlimited);
    const input = if (input_path) |p| try (std.Io.Dir.cwd()).readFileAlloc(init.io, p, alloc, .unlimited) else "";

    if (mode_semantic) {
        const program = try semantic.compile(source, alloc);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = output_path, .data = program });
        var report = try semantic.run(source, input, alloc);
        defer report.deinit(alloc);
        std.debug.print("mode=semantic\nmalbolge_free_cells={d}\nstatus={s}\nsteps={d}\nfinal_d={d}\nstdout_bytes={d}\nwritten={s}\n", .{ program.len, report.status, report.steps, report.final_d, report.stdout.len, output_path });
        // Cross-check contra la referencia BFIR1 (stdout + cinta + puntero).
        try semantic.differential(source, input, alloc);
        std.debug.print("differential=PASS\n", .{});
        return;
    }

    var image = try ir.parse(source, alloc);
    defer image.deinit(alloc);
    std.debug.print("mode=classic-extensional\nbrainfuck_ir_instructions={d}\n", .{image.code.items.len});
    const direct = try bf.run(source, input, alloc);
    var ir_result = try ir_vm.run(&image, input, alloc, 10_000_000);
    defer ir_result.deinit(alloc);
    if (!std.mem.eql(u8, direct, ir_result.output)) return error.IrDifferentialMismatch;
    const expected = ir_result.output;
    std.debug.print("brainfuck_output_bytes={d}\n", .{expected.len});

    generator.verbose = false;
    const program = try generator.generar(expected, 14, alloc);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = output_path, .data = program });

    var memory: [engine.MEM_SIZE]u16 = undefined;
    const result = try engine.runInto(&memory, program, 2_000_000, alloc);
    if (!std.mem.eql(u8, expected, result.output)) return error.GeneratedOutputMismatch;
    std.debug.print("malbolge_output_bytes={d}\nmalbolge_cells={d}\nstatus={s}\nwritten={s}\n", .{ result.output.len, program.len, @tagName(result.status), output_path });
}
