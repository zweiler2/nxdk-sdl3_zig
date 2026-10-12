const std = @import("std");
const nxdk_zig = @import("nxdk_zig");

const Translator = @import("translate_c").Translator;

pub const c_flags: []const []const u8 = &.{
    // "-ffreestanding",
    "-nostdlib",
    // "-fno-builtin",
    "-Wno-builtin-macro-redefined",
    "-DNXDK",
    "-D__STDC__=1",
    "-U__STDC_NO_THREADS__",
};

const c_source =
    \\// pdclib builds INT64_C/UINT64_C from bare token-paste suffixes (e.g.
    \\// `#define _PDCLIB_UINT64_LITERAL ull`), which translate-c cannot translate.
    \\// Restate them via aro's builtin __INT64_C/__UINT64_C, which it can.
    \\#include <stdint.h>
    \\#undef INT64_C
    \\#undef UINT64_C
    \\#define INT64_C(c) __INT64_C(c)
    \\#define UINT64_C(c) __UINT64_C(c)
    \\#include <SDL3/SDL.h>
    \\
;

pub fn build(b: *std.Build) !void {
    const target = b.resolveTargetQuery(nxdk_zig.target_query);
    const optimize = b.standardOptimizeOption(.{});

    const translate_c: Translator = .init(b.dependency("translate_c", .{}), .{
        .c_source_file = b.addWriteFiles().add("c.c", c_source),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
        .extra_args = c_flags,
    });

    const lib = b.addLibrary(.{
        .name = "nxdk_sdl3_zig",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .sanitize_c = .off,
        }),
    });
    b.installArtifact(lib);
    translate_c.linkLibrary(lib);

    for (c_macros) |macro| {
        lib.root_module.addCMacro(macro, "1");
        translate_c.defineCMacro(macro, "1");
    }

    const nxdk_zig_dep = b.dependency("nxdk_zig", .{
        .optimize = optimize,
    });
    nxdk_zig.addCIncludePaths(lib.root_module, nxdk_zig_dep);
    lib.root_module.linkLibrary(nxdk_zig_dep.artifact("nxdk_usb"));

    // --- XGU Begin ---
    {
        const xgu_dep = b.dependency("xgu", .{});
        const xgu_copy = b.addWriteFiles().addCopyDirectory(xgu_dep.path("."), "xgu", .{});
        lib.root_module.addIncludePath(xgu_copy.dirname());
    }
    // --- XGU End ---

    // --- SDL3 Begin ---
    {
        const sdl3_dep = b.dependency("sdl3", .{});

        translate_c.addIncludePath(sdl3_dep.path("include"));
        nxdk_zig.addCIncludePathsTranslateC(translate_c, nxdk_zig_dep);

        lib.installHeadersDirectory(sdl3_dep.path("include/SDL3"), "SDL3", .{});
        lib.root_module.addIncludePath(sdl3_dep.path("include"));
        lib.root_module.addIncludePath(sdl3_dep.path("src"));
        const sdl3_src_dir = try sdl3_dep.builder.root.openDir(b.graph.io, "src", .{ .iterate = true });
        defer sdl3_src_dir.close(b.graph.io);

        for (core_src_paths) |src_path| {
            const src_dir = try sdl3_src_dir.openDir(b.graph.io, src_path, .{ .iterate = true });
            defer src_dir.close(b.graph.io);

            var iter = src_dir.iterate();
            while (try iter.next(b.graph.io)) |entry| {
                if (entry.kind != .file or
                    !std.mem.endsWith(u8, entry.name, ".c") or
                    std.mem.eql(u8, entry.name, "SDL_iostream.c") or
                    std.mem.eql(u8, entry.name, "SDL_steam_virtual_gamepad.c") or
                    std.mem.eql(u8, entry.name, "SDL_systhread.c"))
                {
                    continue;
                }

                lib.root_module.addCSourceFile(.{
                    .language = .c,
                    .file = sdl3_dep.path(b.pathJoin(&.{ "src", src_path, entry.name })),
                    .flags = nxdk_zig.c_flags,
                });
            }
        }
        for (platform_specific_src_paths) |src_path| {
            const src_dir = try sdl3_src_dir.openDir(b.graph.io, src_path, .{ .iterate = true });
            defer src_dir.close(b.graph.io);

            var iter = src_dir.iterate();
            while (try iter.next(b.graph.io)) |entry| {
                if (entry.kind != .file or
                    !std.mem.endsWith(u8, entry.name, ".c") or
                    std.mem.eql(u8, entry.name, "SDL_systhread.c"))
                {
                    continue;
                }

                lib.root_module.addCSourceFile(.{
                    .language = .c,
                    .file = sdl3_dep.path(b.pathJoin(&.{ "src", src_path, entry.name })),
                    .flags = nxdk_zig.c_flags,
                });
            }
        }
        for (platform_specific_src_file_paths) |src_file_path| {
            lib.root_module.addCSourceFile(.{
                .language = .c,
                .file = sdl3_dep.path(b.pathJoin(&.{ "src", src_file_path })),
                .flags = nxdk_zig.c_flags,
            });
        }
    }
    // --- SDL3 End ---

    // --- NXDK-SDL3 Begin ---
    {
        const nxdk_sdl3_dep = b.dependency("nxdk_sdl3", .{});
        lib.root_module.addIncludePath(nxdk_sdl3_dep.path("nxdk_glue"));
        const nxdk_sdl3_glue_dir = try nxdk_sdl3_dep.builder.root.openDir(b.graph.io, "nxdk_glue", .{ .iterate = true });
        defer nxdk_sdl3_glue_dir.close(b.graph.io);

        for (platform_specific_glue_src_paths) |src_path| {
            const src_dir = try nxdk_sdl3_glue_dir.openDir(b.graph.io, src_path, .{ .iterate = true });
            defer src_dir.close(b.graph.io);

            var iter = src_dir.iterate();
            while (try iter.next(b.graph.io)) |entry| {
                if (entry.kind != .file or
                    !std.mem.endsWith(u8, entry.name, ".c"))
                {
                    continue;
                }

                lib.root_module.addCSourceFile(.{
                    .language = .c,
                    .file = nxdk_sdl3_dep.path(b.pathJoin(&.{ "nxdk_glue", src_path, entry.name })),
                    .flags = nxdk_zig.c_flags,
                });
            }
        }
        for (core_glue_src_file_paths) |src_file_path| {
            lib.root_module.addCSourceFile(.{
                .language = .c,
                .file = nxdk_sdl3_dep.path(b.pathJoin(&.{ "nxdk_glue", src_file_path })),
                .flags = nxdk_zig.c_flags,
            });
        }
    }
    // --- NXDK-SDL3 End ---

    // --- Export Translate-C Mod Begin ---
    {
        const module = blk: {
            const m = try b.graph.arena.create(std.Build.Module);
            m.init(b, .{ .existing = translate_c.mod });
            break :blk m;
        };
        const gop = try b.modules.getOrPutValue(
            b.graph.arena,
            b.graph.dupeString("nxdk_sdl3_zig"),
            module,
        );
        if (gop.found_existing) {
            std.debug.panic("A module with the name {q} has already been added to the package. Consider creating a private module with std.Build.createModule", .{"nxdk_sdl3_zig"});
        }
    }
    // --- Export Translate-C Mod End ---
}

const c_macros = [_][]const u8{
    "SDL_DISABLE_ALLOCA",
    "SDL_DISABLE_ANALYZE_MACROS",
    "STBI_NO_SIMD",
    "SDL_DISABLE_MMX",
    "SDL_platform_defines_h_",
};

// --- SDL3 Begin ---
const core_src_paths = [_][]const u8{
    ".",
    "atomic",
    "audio",
    "camera",
    "core",
    "cpuinfo",
    "dialog",
    "dynapi",
    "events",
    "filesystem",
    "gpu",
    "haptic",
    "hidapi",
    "io",
    "io/generic",
    "joystick",
    "libm",
    "loadso",
    "locale",
    "main",
    "misc",
    "power",
    "process",
    "render",
    "sensor",
    "stdlib",
    "storage",
    "test",
    "thread",
    "time",
    "timer",
    "tray",
    "video",
    "video/yuv2rgb",
};

const platform_specific_src_paths = [_][]const u8{
    "main/generic",
    "render/software",
    "storage/generic",
    "thread/windows",
    "camera/dummy",
    "dialog/dummy",
    "haptic/dummy",
    "loadso/dummy",
    "locale/dummy",
    "misc/dummy",
    "process/dummy",
    "sensor/dummy",
    "tray/dummy",
};

const platform_specific_src_file_paths = [_][]const u8{
    "thread/generic/SDL_syscond.c",
    "thread/generic/SDL_sysrwlock.c",
};
// --- SDL3 End ---

// --- NXDK-SDL3 Begin ---
const platform_specific_glue_src_paths = [_][]const u8{
    "audio",
    "filesystem",
    "joystick",
    "render",
    "video",
};

const core_glue_src_file_paths = [_][]const u8{
    "io/SDL_iostream.c",
    "thread/SDL_systhread.c",
    "time/SDL_systime.c",
    "timer/SDL_systimer.c",
    "stubs.c",
    "helper.c",
};
// --- NXDK-SDL3 End ---
