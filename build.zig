const std = @import("std");
const nxdk_zig = @import("nxdk_zig");

pub fn build(b: *std.Build) !void {
    const target = b.resolveTargetQuery(nxdk_zig.target_query);
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("nxdk_sdl3_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "nxdk_sdl3_zig",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(lib);
    mod.linkLibrary(lib);

    for (c_macros) |macro| {
        lib.root_module.addCMacro(macro, "1");
    }

    const nxdk_zig_dep = b.dependency("nxdk_zig", .{
        .optimize = optimize,
    });
    nxdk_zig.addCIncludePaths(lib.root_module, nxdk_zig_dep);

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
        lib.installHeadersDirectory(sdl3_dep.path("include/SDL3"), "SDL3", .{});
        lib.root_module.addIncludePath(sdl3_dep.path("include"));
        lib.root_module.addIncludePath(sdl3_dep.path("src"));
        const sdl3_path = try sdl3_dep.path(".").getPath4(b, null);
        const sdl3_src_dir = try sdl3_path.openDir(b.graph.io, "src", .{ .iterate = true });
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
        const nxdk_sdl3_path = try nxdk_sdl3_dep.path(".").getPath4(b, null);
        const nxdk_sdl3_glue_dir = try nxdk_sdl3_path.openDir(b.graph.io, "nxdk_glue", .{ .iterate = true });
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
