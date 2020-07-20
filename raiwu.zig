const std = @import("std");
const ds = @cImport({
    @cInclude("string.h");
    @cInclude("deepspeech.h");
});

pub const Outerframe = struct {
    fd: std.fs.File,

    pub fn init() !Outerframe {
        const sockfd = try std.os.socket(std.os.AF_UNIX, std.os.SOCK_DGRAM | std.os.SOCK_CLOEXEC, 0);
        errdefer std.os.close(sockfd);
        var addr = try std.net.Address.initUnix("/tmp/lyrics");
        try std.os.connect(sockfd, &addr.any, addr.getOsSockLen());
        return Outerframe{ .fd = std.fs.File{ .handle = sockfd, .io_mode = std.io.mode } };
    }

    pub fn deinit(self: *Outerframe) void {
        self.fd.close();
    }

    pub fn push(self: *Outerframe, message: []const u8) !void {
        try self.fd.writeAll(message);
    }
};

pub fn main() !void {
    var nullModel: ?*ds.ModelState = undefined;
    if (ds.DS_CreateModel("./deepspeech-0.7.4-models.tflite", &nullModel) != 0) {
        return error.FailedToCreateModel;
    }
    const model = nullModel orelse unreachable;
    defer ds.DS_FreeModel(model);
    std.debug.warn("Sample rate: {}\n", .{ds.DS_GetModelSampleRate(model)});

    var nullStream: ?*ds.StreamingState = undefined;
    if (ds.DS_CreateStream(model, &nullStream) != 0) {
        return error.FailedToCreateStream;
    }
    const stream = nullStream orelse unreachable;
    defer ds.DS_FreeStream(stream);

    var bytes = std.fifo.LinearFifo(u8, .{ .Static = 4096 }).init();
    var fifo = std.fifo.LinearFifo(c_short, .{ .Static = 4096 }).init();
    const stderr = std.io.getStdErr();
    const stdin = std.io.getStdIn();

    // var frame = try Outerframe.init();
    // defer frame.deinit();

    const maxMsgLen = 90;
    var buff: [maxMsgLen]u8 = undefined;
    var buf: []u8 = &buff;
    std.mem.copy(u8, buf, " " ** maxMsgLen);

    while (true) {
        // std.debug.warn("{} {}\n", .{ fifo.readableLength(), bytes.readableLength() });
        var chunk = fifo.readableSlice(0);
        if (chunk.len > 0) {
            ds.DS_FeedAudioContent(stream, chunk.ptr, @intCast(c_uint, chunk.len));
            fifo.discard(chunk.len);
            const s = ds.DS_IntermediateDecode(stream);
            defer ds.DS_FreeString(s);
            const n = ds.strlen(s);
            if (n > 0) {
                const newMsg = s[(if (n > maxMsgLen) n - maxMsgLen else 0)..n];
                if (!std.hash_map.eqlString(newMsg, buf)) {
                    std.mem.copy(u8, buf, newMsg);
                    std.debug.warn("{}\n", .{buf});
                }
            }
        } else {
            {
                const writable = bytes.writableSlice(0);
                if (writable.len < 1) {
                    return error.BytesBufferCloggedUp;
                }
                const n = try stdin.read(writable);
                if (n == 0) {
                    return error.StdinGaveUp;
                }
                bytes.update(n);
            }
            {
                const readable = bytes.readableSlice(0);
                comptime {
                    std.debug.assert(@sizeOf(c_short) == 2);
                }
                const writable = fifo.writableSlice(0);
                const nn = std.math.min(@divFloor(readable.len, 2), writable.len);
                var i: usize = 0;
                while (i < nn) : (i += 1) {
                    writable[i] = @ptrCast(*const c_short, @alignCast(@sizeOf(c_short), &readable[i * 2])).*;
                }
                fifo.update(i);
                bytes.discard(i * 2);
            }
        }
    }
}
