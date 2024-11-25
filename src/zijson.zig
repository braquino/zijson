// zig fmt: off
const std = @import("std");
const t = std.testing;
const eql = std.mem.eql;

const ObjectNotFoundError = error{};

const BadPathError = error{};

fn getNextNumber(obj: []const u8) ![]const u8 {
    for (obj, 0..) |c, i| {
        if (c == ',' or c == ' ' or c == '\t' or c == '\n' or c == '}' or c == ']') {
            return obj[0..i];
        }
    }
    return error.ObjectNotFoundError;
}

fn getNextText(obj: []const u8) ![]const u8 {
    var i: usize = 0;
    var c: u8 = undefined;
    while (i < obj.len) : (i += 1) {
        c = obj[i];
        if (c == '\\') {
            i += 1;
            continue;
        }
        if (c == '"' and i > 0) {
            return obj[0 .. i + 1];
        }
    }
    return error.ObjectNotFoundError;
}

fn getNextObject(obj: []const u8) ![]const u8 {
    var obj_open: i32 = 0;
    var quoted = false;

    var i: usize = 0;
    var c: u8 = undefined;
    while (i < obj.len) : (i += 1) {
        c = obj[i];
        if (!quoted) {
            if (c == '"') {
                quoted = true;
                continue;
            }
            if (c == '{' or c == '[') {
                obj_open += 1;
                continue;
            }
            if (c == '}' or c == ']') {
                obj_open -= 1;
                if (obj_open == 0) {
                    return obj[0 .. i + 1];
                }
            }
        } else {
            if (c == '"') {
                quoted = false;
            }
            if (c == '\\') {
                i += 1;
                continue;
            }
        }
    }
    return error.ObjectNotFoundError;
}

fn getNext(obj: []const u8) ![]const u8 {
    if (obj[0] == '{' or obj[0] == '[') return try getNextObject(obj);
    if (obj[0] == '"') return try getNextText(obj);
    return try getNextNumber(obj);
}

fn getObject(obj: []const u8, property: []const u8) ![]const u8 {
    var obj_open: i32 = 0;
    var quoted = false;
    var init = false;
    var found = false;

    var i: usize = 0;
    var c: u8 = undefined;
    while (i < obj.len) : (i += 1) {
        if (obj_open < 0) {
            return error.ObjectNotFoundError;
        }
        c = obj[i];
        if (c == '\\') {
            i += 1;
            continue;
        }
        if (init) {
            if (found) {
                if (c != ':' and c != ' ' and c != '\t' and c != '\n') {
                    return try getNext(obj[i..]);
                }
            } else {
                if (!quoted) {
                    if (c == '"') {
                        quoted = true;
                        continue;
                    }
                    if (c == '{' or c == '[') {
                        obj_open += 1;
                    }
                    if (c == '}' or c == '}') {
                        obj_open -= 1;
                    }
                }
                if (quoted) {
                    if (c == '"') {
                        quoted = false;
                    }
                    if (obj_open == 0 and c == property[0] and obj[i - 1] == '"' and eql(u8, obj[i .. i + property.len], property) and obj[i + property.len] == '"') {
                        found = true;
                        i += property.len;
                        continue;
                    }
                }
            }
        } else {
            if (c == '{' or c == '[') init = true;
        }
    }
    return error.ObjectNotFoundError;
}

fn recPath(obj: []const u8, path: [][]const u8) ![]const u8 {
    if (path.len > 0) {
        std.debug.print("getObject {s} from: {s}\n", .{ path[0], obj });
        const inner_obj = try getObject(obj, path[0]);
        return try recPath(inner_obj, path[1..]);
    } else {
        return obj;
    }
}

pub fn getJSONPathObject(obj: []const u8, JSONPath: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    if (!eql(u8, JSONPath[0..2], "$.")) {
        return error.BadPathError;
    }
    var it = std.mem.splitSequence(u8, JSONPath, ".");
    var path = std.ArrayList([]const u8).init(alloc);
    defer path.deinit();

    while (it.next()) |p| {
        try path.append(p);
    }
    return try recPath(obj, path.items[1..]);
}

export fn getJSONPath(obj: [*:0]const u8, JSONPath: [*:0]const u8, output: [*:0]u8) i32 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const zigObj: []const u8 = std.mem.span(obj);
    const zigJSONPath: []const u8 = std.mem.span(JSONPath);
    const result = getJSONPathObject(zigObj, zigJSONPath, alloc) catch {
        return 1;
    };
    for (result, 0..) |c, i| {
        output[i] = c;
    }
    output[result.len] = 0;
    return 0;
}

test "getObject" {
    const j =
        \\{"foo": 5, "bar": {"hello": 2}, "hello": 3 , "text": "a_text"}
    ;
    const j_hello_lvl1 = try getObject(j, "hello");
    const j_bar = try getObject(j, "bar");
    const j_text = try getObject(j, "text");

    try t.expectEqualStrings("3", j_hello_lvl1);
    try t.expectEqualStrings("{\"hello\": 2}", j_bar);
    try t.expectEqualStrings("\"a_text\"", j_text);
}

test "getJSONPathObject" {
    const alloc = t.allocator;
    const j =
        \\{"foo": 5, "bar": {"hello": 2}, "hello": 3 , "text": "a_text"}
    ;

    const j_hello_lvl2 = try getJSONPathObject(j, "$.bar.hello", alloc);
    try t.expectEqualStrings("2", j_hello_lvl2);

    const json_graph =
        \\{"input": {"hash": 0, "forward_hashes": [1]},
        \\"processes": [{"name": "foo", "python": "print('hello')", "hash": 1, "forward_hashes": [2]}],
        \\"outputs": [{"hash": 2}]
        \\}
    ;
    const j2 = try getJSONPathObject(json_graph, "$.input.hash", alloc);
    try t.expectEqualStrings("0", j2);
}
