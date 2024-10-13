const std = @import("std");
const core = @import("core.zig");

const Fetch = struct {
    user: []const u8,
    host: []const u8,
    os_name_short: []const u8,
    os_name_full: []const u8,
    kernal: []const u8,
    uptime: []const u8,
    shell: []const u8,
    cpu_count: []const u8,
    current_ram: []const u8,
    total_ram: []const u8,
    display: []const u8,
    terminal_size: []const u8,
    desktop_env: []const u8,
    current_storage: []const u8,
    battery: []const u8,

    pub fn init(allocator: std.mem.Allocator) !Fetch {
        var os_release = try core.fileLines("/etc/os-release", allocator);
        const ram = try set_ram_values(allocator);

        const obj = Fetch{
            .user = std.posix.getenv("USER") orelse "Unknown",
            .host = try core.run_shell_cmd(&.{"hostname"}, allocator),
            .os_name_short = os_release.items[2][3..],
            .os_name_full = try std.mem.concat(allocator, u8, &[_][]const u8{
                os_release.items[0][6 .. os_release.items[0].len - 1],
                " ",
                os_release.items[1][9 .. os_release.items[1].len - 1],
            }),
            .kernal = try core.run_shell_cmd(&.{ "uname", "-srn" }, allocator),
            .uptime = try core.run_shell_cmd(&.{ "uptime", "-p" }, allocator),
            .shell = std.posix.getenv("SHELL") orelse "Unknown",
            .cpu_count = try std.fmt.allocPrint(allocator, "{}", .{try std.Thread.getCpuCount()}),
            .current_ram = ram.current,
            .total_ram = ram.total,
            .display = try parse_display(allocator),
            .terminal_size = try std.mem.concat(allocator, u8, &[_][]const u8{
                try core.run_shell_cmd(&.{ "tput", "lines" }, allocator),
                "x",
                try core.run_shell_cmd(&.{ "tput", "cols" }, allocator),
            }),
            .desktop_env = std.posix.getenv("XDG_CURRENT_DESKTOP") orelse "Unknown",
            .battery = try parse_batt(allocator),
            .current_storage = try get_storage(allocator),
        };

        return obj;
    }

    pub fn print(self: Fetch, allocator: std.mem.Allocator) ![]const u8 {
        var lines = std.ArrayList([]const u8).init(allocator);
        defer lines.deinit();

        var longest_len: usize = 0;
        const padding_buf = [_]u8{' '} ** 100;
        const fields = @typeInfo(Fetch).Struct.fields;

        // get longest length val
        inline for (fields) |field| blk: {
            if (std.mem.eql(u8, field.name, "os_name_short")) {
                break :blk;
            }

            const rendered_line = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ field.name, @field(self, field.name) });
            if (rendered_line.len > longest_len) {
                longest_len = rendered_line.len;
            }
        }

        const divider_buf = [_]u8{'-'} ** 100;
        const header_raw = try std.fmt.allocPrint(allocator, "{s}@{s}", .{ colour_string(self.user, allocator), colour_string(self.host, allocator) });
        const divider_raw = try std.fmt.allocPrint(allocator, "{s}", .{divider_buf[0..(self.user.len + self.host.len + 1)]});
        const header = try std.fmt.allocPrint(allocator, "{s}{s}", .{ header_raw, padding_buf[0 .. longest_len - header_raw.len + 22] });
        const divider = try std.fmt.allocPrint(allocator, "{s}{s}", .{ divider_raw, padding_buf[0 .. longest_len - divider_raw.len] });

        const top_buf = [_]u16{'━'} ** 100;
        try lines.append(try std.fmt.allocPrint(allocator, "┏{u}┓\n", .{std.unicode.fmtUtf16Le(top_buf[0 .. longest_len + 2])}));

        try lines.append(try std.fmt.allocPrint(allocator, "┃ {s} ┃\n", .{header}));
        try lines.append(try std.fmt.allocPrint(allocator, "┃ {s} ┃\n", .{divider}));

        inline for (fields) |field| blk: {
            if (std.mem.eql(u8, field.name, "os_name_short")) {
                break :blk;
            }

            const total_len = field.name.len + 2 + @field(self, field.name).len;
            const padding_needed = longest_len - total_len;

            const rendered_line = try std.fmt.allocPrint(
                allocator,
                "┃ {s}: {s}{s} ┃\n",
                .{ 
                    colour_string(field.name, allocator),
                    @field(self, field.name),
                    padding_buf[0..padding_needed] 
                }
            );
            try lines.append(rendered_line);
        }

        const bottom_buf = [_]u16{'━'} ** 100;
        try lines.append(try std.fmt.allocPrint(allocator, "┗{u}┛", .{std.unicode.fmtUtf16Le(bottom_buf[0 .. longest_len + 2])}));

        return try core.mergeLines(try lines.toOwnedSlice(), allocator);
    }
};

fn set_ram_values(allocator: std.mem.Allocator) !struct { current: []const u8, total: []const u8 } {
    var ram_val_iter = std.mem.tokenizeAny(
        u8,
        (try core.splitLines(
            try core.run_shell_cmd(&.{ "free", "-h" }, allocator), allocator)
        ).items[1],
        " "
    );

    _ = ram_val_iter.next();
    const total_ram = ram_val_iter.next().?;
    const current_ram = ram_val_iter.next().?;
    return .{ .current = current_ram, .total = total_ram };
}

fn parse_display(allocator: std.mem.Allocator) ![]const u8 {
    const raw = try core.splitLines(try core.run_shell_cmd(&.{ "xrandr", "--current" }, allocator), allocator);

    for (raw.items) |line| {
        if (line[line.len - 2] == '*') {
            var val = std.mem.tokenizeAny(u8, line, " ");
            return val.next().?;
        }
    }

    return "Unknown";
}

fn parse_batt(allocator: std.mem.Allocator) ![]const u8 {
    var dir = try std.fs.cwd().openDir("/sys/class/power_supply", .{ .iterate = true });
    defer dir.close();

    var dirIterator = dir.iterate();
    while (try dirIterator.next()) |dirContent| {
        if (std.mem.startsWith(u8, dirContent.name, "BAT")) {
            var lines = try core.fileLines(try std.fmt.allocPrint(allocator, "/sys/class/power_supply/{s}/capacity", .{dirContent.name}), allocator);
            const percentage = lines.pop();

            lines = try core.fileLines(try std.fmt.allocPrint(allocator, "/sys/class/power_supply/{s}/status", .{dirContent.name}), allocator);

            return try std.fmt.allocPrint(allocator, "{s}% ({s})", .{ percentage, lines.pop() });
        }
    }

    return "Unknown";
}

fn get_storage(allocator: std.mem.Allocator) ![]const u8 {
    const raw = (try core.splitLines(try core.run_shell_cmd(&.{ "df", "-h", "--output=size,used" }, allocator), allocator)).items[1];

    var nums = std.mem.tokenizeAny(u8, raw, " ");
    const part_1 = nums.next().?;
    const part_2 = nums.next().?;

    return std.fmt.allocPrint(allocator, "{s} / {s}", .{ part_2, part_1 });
}

fn colour_string(s: []const u8, alloc: std.mem.Allocator) []const u8 {
    return std.mem.concat(alloc, u8, &[_][]const u8{ "\x1b[1;32m", s, "\x1b[0m" }) catch s;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fetch_data = try Fetch.init(allocator);
    std.debug.print("{s}\n", .{try fetch_data.print(allocator)});
}
