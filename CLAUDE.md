# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ToastStunt is a MOO server: a network-accessible, multi-user, programmable virtual machine used to run MUDs. Lineage: LambdaMOO -> Stunt (toddsundsted) -> ToastStunt (upstream: github.com/lisdude/toaststunt). This repo is a personal fork that pulls in upstream changes and also carries its own original commits.

## Build

Requires Bison, Perl, gperf, CMake, and (for full feature set) Nettle, Argon2, PCRE2, cURL, Aspell, SQLite3, OpenSSL. There is no native Windows build path documented; build on Linux/WSL/macOS/FreeBSD.

```sh
mkdir build && cd build
cmake ../
make -j2
```

This produces a single `moo` executable. Useful CMake build types (`-DCMAKE_BUILD_TYPE=<type>`):
- `Release` (default): optimized, warnings silenced
- `Debug`: no optimization, debug symbols
- `Warn`: optimized, all warnings enabled (the classic LambdaMOO dev config)
- `LeakCheck`: minimal optimization, AddressSanitizer enabled

`ONLY_32_BITS` and `USE_JEMALLOC` are additional `-D` options (see `CMakeLists.txt`). 32-bit mode is auto-selected on 32-bit targets.

Generated files that are NOT checked in (produced by the build): `parser.cc` (from `src/parser.y` via Bison), `keywords.cc` (from `src/keywords.gperf` via gperf), `version_src.h` and `version_options.h` (from `CMakeModules/version.cmake` / `src/include/version_opt_gen.pl`).

## Running

```sh
./moo <dbase>.db <dbase>.db.new [port]
```

`Minimal.db` and `ToastCore.db` at repo root are seed databases for local dev (a bare-bones core and a ToastCore launch profile, respectively). `restart.sh <dbase-prefix> [port]` rotates `.db`/`.db.new`/`.log` files and relaunches the server in the background; it expects the `moo` binary in the current directory. The gitignored `run/` directory is the conventional place to keep a dev DB and the built executable together.

## Tests

Tests live in `test/` and are Ruby (Test::Unit) scripts that drive a running server over its network protocol and assert on results; a Parslet-based parser (`test/tests/lib/`) turns MOO-code output back into Ruby values.

```sh
cd test
bundle install                      # first time only; needs Ruby 1.9.3+ and Bundler
# symlink echo/sleep/true into test/executables/ (first time only, used by test_exec.rb)
# build the server, copy/symlink the `moo` binary into test/
./moo Test.db /dev/null 9898        # in one terminal, start the server under test
make                                 # in another terminal, runs every test/tests/*.rb
make clean                          # remove the moo binary and /tmp scratch DBs
```

Run a single test file directly: `ruby -r rubygems -Itests/lib tests/test_waif.rb` (from `test/`), or `make test_waif` (the Makefile's `%: tests/%.rb` rule). Server connection settings (host/port/64-bit mode) come from `test/test.yml` and must match how you launched `moo`. `test/tests/*.db` are canned fixture databases used by specific tests (e.g. `test_canned_dbs.rb`, `test_anonymous.rb`).

There is also a smaller, older `test/tests/basic/*/test.in` / `test.out` fixture format (arithmetic/list/object/property/string/value) that isn't part of the Ruby suite.

## Code style

Formatting follows `src/.astylerc` (Artistic Style): 4-space indentation, tabs converted to spaces, padded operators/commas, indented switch blocks, preprocessor blocks indented. Run `astyle --options=src/.astylerc <file>` before committing changes to `.cc`/`.h` files if you have astyle available.

## Architecture

**Compile pipeline (MOO source -> bytecode):** `src/parser.y` (Bison grammar) builds an AST (`ast.cc`/`ast.h`), which `code_gen.cc` compiles into the bytecode format defined in `opcode.h`/`program.h`. `decompile.cc`/`unparse.cc` do the reverse (bytecode -> MOO source), used for `verb_code()`/introspection. `disassemble.cc` renders bytecode for debugging.

**VM / execution:** `execute.cc` and `eval_vm.cc` interpret bytecode; `eval_env.cc` manages variable environments/stack frames. `tasks.cc` schedules MOO tasks (queued, suspended, forked, forked-with-timer via `timers.cc`) and enforces tick/second execution limits (see `options.h` for the limit constants and the lag-threshold/`handle_lagging_task` hook). `exec.cc` is specifically the `exec()` builtin's secure subprocess forking, distinct from the VM's `execute.cc`.

**Object/DB model:** `db.h`/`db_private.h`/`structures.h` define the core value type (`Var`, tagged union over ints/floats/strings/objects/lists/maps/waifs/errors, `structures.h`), object numbers (`Objid`), and the `error` enum (whose ordinal values are persisted in the DB — never reorder existing entries, only append). `db_objects.cc`, `db_properties.cc`, `db_verbs.cc` implement the in-memory object graph (parents/children, properties, verb definitions); `db_file.cc`/`db_io.cc` handle loading/checkpointing the on-disk `.db` format. `garbage.cc` implements cycle collection for anonymous objects (`ENABLE_GC` in `options.h`); `quota.cc` enforces ownership quotas.

**Built-in functions:** every builtin group has a `register_xxx(void)` function (declared in `src/include/bf_register.h`, e.g. `register_list`, `register_map`, `register_waif`, `register_sqlite`) that's called once at startup from the `bi_function_registries` table in `functions.cc`. To add a new builtin, add it inside the relevant `register_xxx()` (or create a new one and wire it into both `bf_register.h` and the table in `functions.cc`), following the `register_function(name, minargs, maxargs, handler, ...)` pattern used throughout files like `list.cc`, `map.cc`, `waif.cc`, `json.cc`, `sqlite.cc`.

**Networking:** `network.cc` (connection-level protocol handling, telnet IAC/state machine, TLS) and `net_mplex.cc` (poll/select-based multiplexing) sit below `server.cc`, which owns the main loop, command-line parsing, checkpointing, and signal handling. `http_parser.c` (vendored) is used for in-server HTTP request/response parsing (map datatype output).

**Data types with their own modules:** `list.cc`/`map.cc`/`collection.cc` (list/map/generic collection ops, e.g. `maphaskey`), `str_intern.cc` (string interning), `waif.cc` (the WAIF lightweight-object type), `streams.cc` (the `Stream` string-builder used pervasively for building output).

**Threading:** `background.cc` provides the thread-pool-backed "run this builtin off the main thread" mechanism (`src/dependencies/thpool.c`); `set_thread_mode()` toggles it per-verb. Builtins opted into threading include `sqlite_query`/`sqlite_execute`, `argon2`/`argon2_verify`, `sort`, and DNS lookups — see `docs/README.md` and `docs/ChangeLog.md` for which functions are threaded in the current version, since this has changed across releases (e.g. `occupants()`/`locate_by_name()` were de-threaded after unsafe DB access was found).

**Vendored dependencies** (`src/dependencies/`): `yajl` (JSON, used by `json.cc`), `pcrs.c`/`pcre_moo.cc` (PCRE2-based regex substitution and the `pcre_match`/`pcre_replace` builtins), `crypt` (crypt_blowfish/bcrypt), `sosemanuk.c` (CSPRNG), `linenoise.c` (emergency-wizard-mode line editing), `thpool.c` (thread pool), `strnatcmp.c` (natural sort).

## Documentation map

- `docs/ChangeLog.md` — versioned changelog; check here before assuming a builtin's behavior matches an older release.
- `docs/Features/new_builtins.md`, `new_options.md`, `new_miscellaneous.md` — living docs for everything ToastStunt adds on top of vanilla Stunt/LambdaMOO.
- `docs/ServerDevelopment/AddingNewMOOTypes.txt` — every place in the source that needs updating when adding a new MOO value type.
- `docs/ServerDevelopment/MOOCodeSequences.txt` — how language constructs lower to bytecode.
- `docs/ServerDevelopment/version_src.txt` — how `version_src.h`/`server_version()` metadata works.
- `docs/Legacy/README/README.Stunt` and `README.LambdaMOO` — background on inherited functionality (multiple inheritance, anonymous objects, map datatype, JSON, crypto, FileIO, `exec()`, primitive-type verb calls, HTTP parsing, bitwise ops, the Ruby test framework).
