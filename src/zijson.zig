// zig fmt: off
const std = @import("std");
const re = @cImport({
    @cInclude("regex.h");
});
const t = std.testing;
const eql = std.mem.eql;

const ObjectNotFoundError = error{};

const BadPathError = error{};

const NotImplementedError = error{};

const PathType = enum {
    simple,         // simple path
    subscript,      // a path + an index
    star,           // a path + a '*' (star) index
};

const SubscriptPath = struct {
    path: []const u8,
    subs: i32,
};

var re_compiled: bool = false;
var re_subscript: re.regex_t = undefined;

// Must be called before the use of the regex
fn compileRegex() void {
    if (!re_compiled) {
        var err_code: c_int = undefined;
        err_code = re.regcomp(&re_subscript, "^\\(.*\\)\\[\\([0-9,\\*]*\\)\\]$", 0);
        if (err_code != 0) {
            std.debug.panic("error compiling regex re_subscript, code: {d}\n", .{err_code});
        }
        std.debug.print("all regex compiled\n", .{});
        re_compiled = true;
    }
}

// Considering the 'path_segment' is of type 'subscript' or 'star', returns your componets (path and subscription)
fn getSubscriptComp(path_segment: []const u8, alloc: std.mem.Allocator) !SubscriptPath {
    compileRegex();
    const c_path_segment = try alloc.dupeZ(u8, path_segment);
    defer alloc.free(c_path_segment);
    var re_code: c_int = undefined;
    var re_match_subsc: [3]re.regmatch_t = undefined;
    re_code = re.regexec(&re_subscript, c_path_segment.ptr, 3, &re_match_subsc, 0);
    if (re_code != re.REG_NOMATCH) {
        var rm_so: usize = undefined;
        var rm_eo: usize = undefined;
        
        rm_so = @intCast(re_match_subsc[1].rm_so);
        rm_eo = @intCast(re_match_subsc[1].rm_eo);
        const path = path_segment[rm_so..rm_eo];

        rm_so = @intCast(re_match_subsc[2].rm_so);
        rm_eo = @intCast(re_match_subsc[2].rm_eo);
        var subs: i32 = -1;
        if (path_segment[rm_so] != '*')
            subs = try std.fmt.parseInt(i32, path_segment[rm_so..rm_eo], 10);
        
        return SubscriptPath{
            .path = path,
            .subs = subs
        };
    }
    return error.BadPathError;
}

// Given a 'path_segment', returns its type
fn checkPathType(path_segment: []const u8, alloc: std.mem.Allocator) !PathType {
    compileRegex();
    const c_path_segment = try alloc.dupeZ(u8, path_segment);
    defer alloc.free(c_path_segment);
    var re_code: c_int = undefined;
    var re_match_subsc: [3]re.regmatch_t = undefined;
    re_code = re.regexec(&re_subscript, c_path_segment.ptr, 3, &re_match_subsc, 0);
    std.debug.print("for path_segment {s}, code: {d}\n", .{c_path_segment, re_code});
    if (re_code != re.REG_NOMATCH) {
        const rm_so: usize = @intCast(re_match_subsc[2].rm_so);
        if (path_segment[rm_so] == '*')
            return PathType.star;
        return PathType.subscript;
    }
    return PathType.simple;
}

// Returns the complete next number found, must start from the first object's char
fn getNextNumber(obj: []const u8) ![]const u8 {
    for (obj, 0..) |c, i| {
        if (c == ',' or c == ' ' or c == '\t' or c == '\n' or c == '}' or c == ']') {
            return obj[0..i];
        }
    }
    return error.ObjectNotFoundError;
}

// Returns the complete next text found, must start from the first object's char
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

// Returns the complete next object or array found, must start from the first object's char
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

// Returns the complete next element found, must start from the first object's char
fn getNext(obj: []const u8) ![]const u8 {
    if (obj[0] == '{' or obj[0] == '[') return try getNextObject(obj);
    if (obj[0] == '"') return try getNextText(obj);
    return try getNextNumber(obj);
}

// Returns a component of a list with the 'index' number
fn getSubscript(obj: []const u8, index: i32) ![]const u8 {
    var cur_obj: []const u8 = undefined;
    var init = false;
    var cur_idx: i32 = 0;
    var i: usize = 0;
    var c: u8 = undefined;
    while (i < obj.len) : (i += 1) {
        c = obj[i];
        if (init) {
            if (c != ',' and c != ' ' and c != '\t' and c != '\n') {
                cur_obj = try getNext(obj[i..]);
                if (cur_idx == index) {
                    return cur_obj;
                } else {
                    cur_idx += 1;
                    i += cur_obj.len;
                    continue;
                }
            }
        } else {
            if (c == '[') {
                init = true;
            }
        }
    }
    return error.ObjectNotFoundError;
}

// Returns an inner object with the 'property' key
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
                    if (c == '}' or c == ']') {
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

fn recPath(obj: []const u8, path: [][]const u8, alloc: std.mem.Allocator) ![]const u8 {
    if (path.len > 0) {
        std.debug.print("getObject {s} from: {s}\n", .{ path[0], obj });
        const pathType = try checkPathType(path[0], alloc);
        if (pathType == PathType.simple) {
            const inner_obj = try getObject(obj, path[0]);
            return try recPath(inner_obj, path[1..], alloc);
        }
        if (pathType == PathType.subscript) {
            const subsComp = try getSubscriptComp(path[0], alloc);
            const inner_obj = try getObject(obj, subsComp.path);
            const inner_subs = try getSubscript(inner_obj, subsComp.subs);
            return try recPath(inner_subs, path[1..], alloc);
        }
        return error.NotImplementedError;
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
    return try recPath(obj, path.items[1..], alloc);
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
        \\"processes": [
        \\  {"name": "foo", "python": "print('hello')", "hash": 1, "forward_hashes": [2]},
        \\  {"name": "bar", "python": "print('bie')", "hash": 2, "forward_hashes": [2]},
        \\  {"name": "iou", "python": "print('ciao')", "hash": 3, "forward_hashes": [3]}
        \\],
        \\"outputs": [{"hash": 2}]
        \\}
    ;
    const j2 = try getJSONPathObject(json_graph, "$.input.hash", alloc);
    try t.expectEqualStrings("0", j2);

    const j3 = try getJSONPathObject(json_graph, "$.processes[1]", alloc);
    try t.expectEqualStrings(
        "{\"name\": \"bar\", \"python\": \"print('bie')\", \"hash\": 2, \"forward_hashes\": [2]}", 
        j3,
    );

    const j4 = try getJSONPathObject(json_graph, "$.processes[2].forward_hashes[0]", alloc);
    try t.expectEqualStrings("3", j4);
}

test "checkPathType" {
    const alloc = t.allocator;
    try t.expectEqual(PathType.subscript, try checkPathType("foo[56]", alloc));
    try t.expectEqual(PathType.subscript, try checkPathType("foo[0]", alloc));
    try t.expectEqual(PathType.star, try checkPathType("foo[*]", alloc));
    try t.expectEqual(PathType.simple, try checkPathType("bar", alloc));
}

test "getSubscriptComp" {
    const alloc = t.allocator;
    const subs = try getSubscriptComp("subs[*]", alloc);
    try t.expectEqualStrings("subs", subs.path);
    try t.expectEqual(-1, subs.subs);

    const subs2 = try getSubscriptComp("subs[789]", alloc);
    try t.expectEqualStrings("subs", subs2.path);
    try t.expectEqual(789, subs2.subs);
}
