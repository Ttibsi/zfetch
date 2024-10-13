const std = @import("std");

pub fn fileLines(file_path: []const u8, alloc: std.mem.Allocator) !std.ArrayList([]const u8) {
    const file = try std.fs.cwd().openFile(file_path, .{});
    const content = try file.reader().readAllAlloc(alloc, 1_000_000_000);

    var lines = std.ArrayList([]const u8).init(alloc);
    var iterator = std.mem.tokenize(u8, content, "\n");

    while (iterator.next()) |line| {
        try lines.append(line);
    }

    return lines;
}

pub fn splitLines(content: []const u8, alloc: std.mem.Allocator) !std.ArrayList([]const u8) {
    var lines = std.ArrayList([]const u8).init(alloc);
    var iterator = std.mem.tokenize(u8, content, "\n");

    while (iterator.next()) |line| {
        try lines.append(line);
    }

    return lines;
}

pub fn mergeLines(content: [][]const u8, allocator: std.mem.Allocator) ![]const u8 {
    var arr = std.ArrayList(u8).init(allocator);
    for (content) |line| {
        try arr.appendSlice(line);
    }
    return arr.toOwnedSlice();
}

pub fn run_shell_cmd(cmd: []const []const u8, alloc: std.mem.Allocator) ![]const u8 {
    var child = std.process.Child.init(cmd, alloc);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    var stdout = std.ArrayList(u8).init(alloc);
    var stderr = std.ArrayList(u8).init(alloc);
    defer {
        stdout.deinit();
        stderr.deinit();
    }

    try child.spawn();
    try child.collectOutput(&stdout, &stderr, 51200);
    const ret = try stdout.toOwnedSlice();
    return ret[0 .. ret.len - 1];
}
