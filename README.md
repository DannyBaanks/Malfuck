# Malfuck

Compilador **Brainfuck → Malbolge** en Zig 0.16, autocontenido. Miembro
puente de la familia `-bolge`: toma Brainfuck y produce programas Malbolge.

Tiene dos backends con semántica muy distinta. Leer antes de citar.

## Uso

```powershell
zig build-exe src\main.zig -O ReleaseFast
Move-Item main.exe malfuck.exe

# Classic extensional (por defecto)
malfuck.exe examples\five.bf five.mal
malfuck.exe examples\echo.bf echo_classic.mal examples\echo.in

# Semántico (Malbolge Free)
malfuck.exe examples\hello.bf hello_sem.mal --semantic
malfuck.exe examples\echo.bf echo_sem.mal examples\echo.in --semantic
```

## Backend `--semantic` (el verdadero)

`BF → IR → BFIR1 → HeLL (lmao-lite) → Malbolge Free`, ejecutado y verificado
con el core `malbolge_free` asistido (`width=10`, `fixed`, `TAPE_BASE`).

- Conserva cinta, puntero, loops e **input en runtime**: el `.mal` compilado
  responde a entradas nuevas, no trae la salida horneada.
- Tests (`zig test src\semantic.zig -O ReleaseSafe`, 4/4 PASS):
  diferencial de 5 programas contra la referencia BFIR1 comparando
  stdout + cinta de 256 celdas + puntero + terminación; Hello World!;
  el mismo `.mal` de `,[.,]` ejecutado dos veces con inputs distintos
  (`XY` → `XY`, `1234` → `1234`).

Resultado medido (2026-09-12, zig 0.16.0):

```text
hello.bf --semantic: 794 celdas, HALTED, 3092 steps, stdout "Hello World!", differential=PASS
echo.bf  --semantic: 22 celdas, HALTED, stdout ABC\n, differential=PASS
```

**Dependencia de runtime:** el programa emitido usa la op asistida
`TAPE_BASE` (Free). **No lo ejecutes con una VM Classic** (vm.c, Zigbolge):
el contract no incluye esa op y el resultado no sería válido.

## Backend Classic extensional (default)

Ejecuta el BF (loops e input incluidos, vía `src/ir_vm.zig` validado contra
el intérprete directo) y sintetiza con el generador un `.mal` **Classic**
(3^10) que reproduce exactamente los bytes de salida de ESA ejecución.

```text
five.bf (++++++.): 33 celdas Classic, salida 0x05, VInstruction, 33 steps
echo.bf con ABC\n:  521 celdas Classic, salida ABC\n, halted
```

Convertible a artefacto verificado con cualquier VM Classic (Zigbolge
lo ejecuta byte-exacto).

## Limites honestos

| Claim | Estado |
|---|---|
| BF→Malbolge Free con semántica completa (5 programas, differential) | **PASS** |
| `.mal` compilado reusado con input nuevo en runtime | **PASS** |
| BF→Malbolge **Classic** semántico (loops/input conservados, ejecutable en vm.c) | **NOT_IMPLEMENTED** |
| Self-hosting (compiler.bf compilándose a sí mismo) | **NOT_DEMONSTRATED** (límite TAPE_BASE 256 celdas, ver malbolge-free m7) |
| Turing-completeness nueva | **NOT_DEMONSTRATED** (esta infra es requerimiento, no prueba) |

## Procedencia

Pipeline semántico copiado de `malbolge-free` (`src/hell.zig`,
`src/bfir1_backend.zig`, `src/malbolge_free.zig`, `tests/bf_to_ir.zig`,
`tests/bf_ir_image.zig`, `tests/bf_ir_vm.zig`, `tests/bf_interpreter.zig` →
`src/bf_reference.zig`) regla L0 "copiar, no integrar": la copia es código
propio de este repo, sin dependencias cruzadas. El generador Classic
extensional y su engine vienen de `Malbolge-Translator/zig/src`.
