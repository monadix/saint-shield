// SPDX-License-Identifier: Apache-2.0
//! Bounded classic-PCAP parsing and deterministic fixture writing.
//!
//! This module intentionally implements only the classic 24-byte global
//! header and 16-byte record-header format. PCAPNG and live capture are
//! rejected as unsupported. Parsing is allocation-free; callers that need
//! stable storage can use `Capture.parseAlloc` and release it with `deinit`.

const std = @import("std");

const global_header_len = 24;
const record_header_len = 16;
const magic_big_micro = [_]u8{ 0xa1, 0xb2, 0xc3, 0xd4 };
const magic_little_micro = [_]u8{ 0xd4, 0xc3, 0xb2, 0xa1 };
const magic_big_nano = [_]u8{ 0xa1, 0xb2, 0x3c, 0x4d };
const magic_little_nano = [_]u8{ 0x4d, 0x3c, 0xb2, 0xa1 };

/// Byte order encoded by the classic-PCAP magic number.
pub const ByteOrder = enum {
    little,
    big,

    fn toEndian(self: ByteOrder) std.builtin.Endian {
        return switch (self) {
            .little => .little,
            .big => .big,
        };
    }
};

/// Fractional-second resolution encoded by the classic-PCAP magic number.
pub const TimestampResolution = enum {
    microseconds,
    nanoseconds,

    fn fractionLimit(self: TimestampResolution) u32 {
        return switch (self) {
            .microseconds => 1_000_000,
            .nanoseconds => 1_000_000_000,
        };
    }
};

/// Explicit policy for records whose captured payload length is zero.
pub const ZeroLengthPolicy = enum {
    allow,
    reject,
};

/// Hard limits applied before a parser or writer accepts capture contents.
pub const Limits = struct {
    max_capture_bytes: u64,
    max_records: u64,
    max_snaplen: u32,
    zero_length_records: ZeroLengthPolicy,
};

/// Stable broad category for a detailed parse failure.
pub const ErrorClass = enum {
    truncated,
    malformed,
    unsupported,
    limit,
    arithmetic,
};

/// Detailed failures for untrusted classic-PCAP input.
pub const ParseError = error{
    TruncatedGlobalHeader,
    TruncatedRecordHeader,
    TruncatedRecordData,
    MalformedSnaplen,
    MalformedTimestamp,
    MalformedRecordLength,
    ZeroLengthRecordRejected,
    UnsupportedMagic,
    UnsupportedVersion,
    CaptureBytesLimitExceeded,
    RecordLimitExceeded,
    SnaplenLimitExceeded,
    ArithmeticOverflow,
};

/// Returns the stable broad category for a detailed parse failure.
pub fn classifyError(err: ParseError) ErrorClass {
    return switch (err) {
        error.TruncatedGlobalHeader,
        error.TruncatedRecordHeader,
        error.TruncatedRecordData,
        => .truncated,

        error.MalformedSnaplen,
        error.MalformedTimestamp,
        error.MalformedRecordLength,
        error.ZeroLengthRecordRejected,
        => .malformed,

        error.UnsupportedMagic,
        error.UnsupportedVersion,
        => .unsupported,

        error.CaptureBytesLimitExceeded,
        error.RecordLimitExceeded,
        error.SnaplenLimitExceeded,
        => .limit,

        error.ArithmeticOverflow => .arithmetic,
    };
}

/// Parsed classic-PCAP global header fields.
pub const GlobalHeader = struct {
    byte_order: ByteOrder,
    timestamp_resolution: TimestampResolution,
    timezone_correction: i32,
    timestamp_accuracy: u32,
    snaplen: u32,
    link_type: u32,
};

/// Capture timestamp retained as optional fixture metadata.
pub const Timestamp = struct {
    seconds: u32,
    fraction: u32,
    resolution: TimestampResolution,
};

/// One allocation-free record borrowed from the parser input.
pub const RecordView = struct {
    timestamp: ?Timestamp,
    original_len: u32,
    data: []const u8,
};

/// Allocation-free, forward-only classic-PCAP parser.
pub const Parser = struct {
    bytes: []const u8,
    header: GlobalHeader,
    limits: Limits,
    offset: usize = global_header_len,
    record_count: u64 = 0,
    captured_bytes: u64 = 0,

    /// Validates the global header and prepares bounded record iteration.
    pub fn init(bytes: []const u8, limits: Limits) ParseError!Parser {
        if (bytes.len < global_header_len) return error.TruncatedGlobalHeader;

        const encoding = decodeMagic(bytes[0..4]) orelse
            return error.UnsupportedMagic;
        const byte_order = encoding.byte_order.toEndian();
        const version_major = readInt(u16, bytes, 4, byte_order);
        const version_minor = readInt(u16, bytes, 6, byte_order);
        if (version_major != 2 or version_minor != 4)
            return error.UnsupportedVersion;

        const snaplen = readInt(u32, bytes, 16, byte_order);
        if (snaplen == 0) return error.MalformedSnaplen;
        if (snaplen > limits.max_snaplen)
            return error.SnaplenLimitExceeded;

        return .{
            .bytes = bytes,
            .header = .{
                .byte_order = encoding.byte_order,
                .timestamp_resolution = encoding.timestamp_resolution,
                .timezone_correction = readInt(i32, bytes, 8, byte_order),
                .timestamp_accuracy = readInt(u32, bytes, 12, byte_order),
                .snaplen = snaplen,
                .link_type = readInt(u32, bytes, 20, byte_order),
            },
            .limits = limits,
        };
    }

    /// Returns the next borrowed record, or null at an exact record boundary.
    pub fn next(self: *Parser) ParseError!?RecordView {
        if (self.offset == self.bytes.len) return null;

        const header_end = std.math.add(usize, self.offset, record_header_len) catch
            return error.ArithmeticOverflow;
        if (header_end > self.bytes.len) return error.TruncatedRecordHeader;

        const byte_order = self.header.byte_order.toEndian();
        const seconds = readInt(u32, self.bytes, self.offset, byte_order);
        const fraction = readInt(u32, self.bytes, self.offset + 4, byte_order);
        const captured_len = readInt(u32, self.bytes, self.offset + 8, byte_order);
        const original_len = readInt(u32, self.bytes, self.offset + 12, byte_order);

        if (fraction >= self.header.timestamp_resolution.fractionLimit())
            return error.MalformedTimestamp;
        if (captured_len > original_len or captured_len > self.header.snaplen)
            return error.MalformedRecordLength;
        if (captured_len == 0 and self.limits.zero_length_records == .reject)
            return error.ZeroLengthRecordRejected;

        const next_record_count = std.math.add(u64, self.record_count, 1) catch
            return error.ArithmeticOverflow;
        if (next_record_count > self.limits.max_records)
            return error.RecordLimitExceeded;

        const next_captured_bytes = std.math.add(
            u64,
            self.captured_bytes,
            captured_len,
        ) catch return error.ArithmeticOverflow;
        if (next_captured_bytes > self.limits.max_capture_bytes)
            return error.CaptureBytesLimitExceeded;

        const data_end = std.math.add(usize, header_end, captured_len) catch
            return error.ArithmeticOverflow;
        if (data_end > self.bytes.len) return error.TruncatedRecordData;

        const record = RecordView{
            .timestamp = .{
                .seconds = seconds,
                .fraction = fraction,
                .resolution = self.header.timestamp_resolution,
            },
            .original_len = original_len,
            .data = self.bytes[header_end..data_end],
        };
        self.offset = data_end;
        self.record_count = next_record_count;
        self.captured_bytes = next_captured_bytes;
        return record;
    }
};

/// One record whose data is owned by its containing `Capture`.
pub const OwnedRecord = struct {
    timestamp: ?Timestamp,
    original_len: u32,
    data: []const u8,
};

/// Owned capture storage for fixtures that must outlive their source bytes.
pub const Capture = struct {
    header: GlobalHeader,
    records: []OwnedRecord,
    storage: []u8,

    /// Parses and copies a complete bounded capture with caller-owned storage.
    pub fn parseAlloc(
        allocator: std.mem.Allocator,
        bytes: []const u8,
        limits: Limits,
    ) (ParseError || std.mem.Allocator.Error)!Capture {
        var validation = try Parser.init(bytes, limits);
        while (try validation.next()) |_| {}

        const record_count = std.math.cast(usize, validation.record_count) orelse
            return error.ArithmeticOverflow;
        const captured_bytes = std.math.cast(usize, validation.captured_bytes) orelse
            return error.ArithmeticOverflow;

        const records = try allocator.alloc(OwnedRecord, record_count);
        errdefer allocator.free(records);
        const storage = try allocator.alloc(u8, captured_bytes);
        errdefer allocator.free(storage);

        var parser = try Parser.init(bytes, limits);
        var record_index: usize = 0;
        var storage_offset: usize = 0;
        while (try parser.next()) |record| : (record_index += 1) {
            const storage_end = std.math.add(
                usize,
                storage_offset,
                record.data.len,
            ) catch return error.ArithmeticOverflow;
            @memcpy(storage[storage_offset..storage_end], record.data);
            records[record_index] = .{
                .timestamp = record.timestamp,
                .original_len = record.original_len,
                .data = storage[storage_offset..storage_end],
            };
            storage_offset = storage_end;
        }

        return .{
            .header = parser.header,
            .records = records,
            .storage = storage,
        };
    }

    /// Releases all memory owned by this capture.
    pub fn deinit(self: *Capture, allocator: std.mem.Allocator) void {
        allocator.free(self.storage);
        allocator.free(self.records);
        self.* = undefined;
    }
};

/// Configuration for reproducible classic-PCAP output.
pub const WriterConfig = struct {
    byte_order: ByteOrder,
    timestamp_resolution: TimestampResolution,
    snaplen: u32,
    link_type: u32,
};

/// One record supplied to the deterministic writer.
pub const RecordInput = struct {
    timestamp: ?Timestamp = null,
    original_len: ?u32 = null,
    data: []const u8,
};

/// Detailed deterministic-writer validation failures.
pub const WriteError = error{
    InvalidSnaplen,
    InvalidTimestamp,
    TimestampResolutionMismatch,
    RecordTooLarge,
    OriginalLengthTooSmall,
    ZeroLengthRecordRejected,
    CaptureBytesLimitExceeded,
    RecordLimitExceeded,
    SnaplenLimitExceeded,
    ArithmeticOverflow,
};

/// Encodes records into one deterministic, caller-owned classic-PCAP buffer.
///
/// The writer always emits version 2.4 with zero timezone correction and zero
/// timestamp accuracy. A missing record timestamp is encoded as zero seconds
/// and zero fractional seconds.
pub fn writeAlloc(
    allocator: std.mem.Allocator,
    config: WriterConfig,
    limits: Limits,
    records: []const RecordInput,
) (WriteError || std.mem.Allocator.Error)![]u8 {
    if (config.snaplen == 0) return error.InvalidSnaplen;
    if (config.snaplen > limits.max_snaplen)
        return error.SnaplenLimitExceeded;
    if (records.len > limits.max_records)
        return error.RecordLimitExceeded;

    var capture_bytes: u64 = 0;
    var output_len: usize = global_header_len;
    for (records) |record| {
        const captured_len = std.math.cast(u32, record.data.len) orelse
            return error.RecordTooLarge;
        if (captured_len > config.snaplen) return error.RecordTooLarge;
        if (captured_len == 0 and limits.zero_length_records == .reject)
            return error.ZeroLengthRecordRejected;
        const original_len = record.original_len orelse captured_len;
        if (original_len < captured_len) return error.OriginalLengthTooSmall;
        try validateWriterTimestamp(record.timestamp, config.timestamp_resolution);

        capture_bytes = std.math.add(u64, capture_bytes, captured_len) catch
            return error.ArithmeticOverflow;
        if (capture_bytes > limits.max_capture_bytes)
            return error.CaptureBytesLimitExceeded;
        output_len = std.math.add(usize, output_len, record_header_len) catch
            return error.ArithmeticOverflow;
        output_len = std.math.add(usize, output_len, record.data.len) catch
            return error.ArithmeticOverflow;
    }

    const output = try allocator.alloc(u8, output_len);
    errdefer allocator.free(output);
    const byte_order = config.byte_order.toEndian();
    @memcpy(output[0..4], magicFor(config.byte_order, config.timestamp_resolution));
    writeInt(u16, output, 4, 2, byte_order);
    writeInt(u16, output, 6, 4, byte_order);
    writeInt(i32, output, 8, 0, byte_order);
    writeInt(u32, output, 12, 0, byte_order);
    writeInt(u32, output, 16, config.snaplen, byte_order);
    writeInt(u32, output, 20, config.link_type, byte_order);

    var offset: usize = global_header_len;
    for (records) |record| {
        const timestamp = record.timestamp orelse Timestamp{
            .seconds = 0,
            .fraction = 0,
            .resolution = config.timestamp_resolution,
        };
        const captured_len: u32 = @intCast(record.data.len);
        const original_len = record.original_len orelse captured_len;
        writeInt(u32, output, offset, timestamp.seconds, byte_order);
        writeInt(u32, output, offset + 4, timestamp.fraction, byte_order);
        writeInt(u32, output, offset + 8, captured_len, byte_order);
        writeInt(u32, output, offset + 12, original_len, byte_order);
        offset += record_header_len;
        @memcpy(output[offset .. offset + record.data.len], record.data);
        offset += record.data.len;
    }
    std.debug.assert(offset == output.len);
    return output;
}

const Encoding = struct {
    byte_order: ByteOrder,
    timestamp_resolution: TimestampResolution,
};

fn decodeMagic(bytes: []const u8) ?Encoding {
    if (std.mem.eql(u8, bytes, &magic_little_micro))
        return .{ .byte_order = .little, .timestamp_resolution = .microseconds };
    if (std.mem.eql(u8, bytes, &magic_big_micro))
        return .{ .byte_order = .big, .timestamp_resolution = .microseconds };
    if (std.mem.eql(u8, bytes, &magic_little_nano))
        return .{ .byte_order = .little, .timestamp_resolution = .nanoseconds };
    if (std.mem.eql(u8, bytes, &magic_big_nano))
        return .{ .byte_order = .big, .timestamp_resolution = .nanoseconds };
    return null;
}

fn magicFor(order: ByteOrder, resolution: TimestampResolution) *const [4]u8 {
    return switch (order) {
        .little => switch (resolution) {
            .microseconds => &magic_little_micro,
            .nanoseconds => &magic_little_nano,
        },
        .big => switch (resolution) {
            .microseconds => &magic_big_micro,
            .nanoseconds => &magic_big_nano,
        },
    };
}

fn validateWriterTimestamp(
    timestamp: ?Timestamp,
    resolution: TimestampResolution,
) WriteError!void {
    const value = timestamp orelse return;
    if (value.resolution != resolution)
        return error.TimestampResolutionMismatch;
    if (value.fraction >= resolution.fractionLimit())
        return error.InvalidTimestamp;
}

fn readInt(
    comptime T: type,
    bytes: []const u8,
    offset: usize,
    byte_order: std.builtin.Endian,
) T {
    const size = @divExact(@bitSizeOf(T), 8);
    const pointer: *const [size]u8 = @ptrCast(bytes[offset..].ptr);
    return std.mem.readInt(T, pointer, byte_order);
}

fn writeInt(
    comptime T: type,
    bytes: []u8,
    offset: usize,
    value: T,
    byte_order: std.builtin.Endian,
) void {
    const size = @divExact(@bitSizeOf(T), 8);
    const pointer: *[size]u8 = @ptrCast(bytes[offset..].ptr);
    std.mem.writeInt(T, pointer, value, byte_order);
}

const generous_limits = Limits{
    .max_capture_bytes = 4096,
    .max_records = 16,
    .max_snaplen = 2048,
    .zero_length_records = .allow,
};

fn oneRecordCapture(
    allocator: std.mem.Allocator,
    order: ByteOrder,
    resolution: TimestampResolution,
) ![]u8 {
    return writeAlloc(allocator, .{
        .byte_order = order,
        .timestamp_resolution = resolution,
        .snaplen = 128,
        .link_type = 1,
    }, generous_limits, &.{.{
        .timestamp = .{
            .seconds = 7,
            .fraction = if (resolution == .microseconds) 123_456 else 123_456_789,
            .resolution = resolution,
        },
        .original_len = 5,
        .data = &.{ 0xde, 0xad, 0xbe },
    }});
}

test "classic PCAP parses both byte orders and timestamp resolutions" {
    inline for (.{ ByteOrder.little, ByteOrder.big }) |order| {
        inline for (.{ TimestampResolution.microseconds, TimestampResolution.nanoseconds }) |resolution| {
            const bytes = try oneRecordCapture(std.testing.allocator, order, resolution);
            defer std.testing.allocator.free(bytes);

            var parser = try Parser.init(bytes, generous_limits);
            try std.testing.expectEqual(order, parser.header.byte_order);
            try std.testing.expectEqual(resolution, parser.header.timestamp_resolution);
            try std.testing.expectEqual(@as(u32, 128), parser.header.snaplen);
            try std.testing.expectEqual(@as(u32, 1), parser.header.link_type);
            const record = (try parser.next()).?;
            try std.testing.expectEqual(@as(u32, 5), record.original_len);
            try std.testing.expectEqualSlices(u8, &.{ 0xde, 0xad, 0xbe }, record.data);
            try std.testing.expectEqual(resolution, record.timestamp.?.resolution);
            try std.testing.expect((try parser.next()) == null);
        }
    }
}

test "classic PCAP distinguishes every representable truncation offset" {
    const bytes = try oneRecordCapture(
        std.testing.allocator,
        .little,
        .microseconds,
    );
    defer std.testing.allocator.free(bytes);

    for (0..global_header_len) |cut| {
        try std.testing.expectError(
            error.TruncatedGlobalHeader,
            Parser.init(bytes[0..cut], generous_limits),
        );
    }

    var header_only = try Parser.init(bytes[0..global_header_len], generous_limits);
    try std.testing.expect((try header_only.next()) == null);
    for (global_header_len + 1..global_header_len + record_header_len) |cut| {
        var parser = try Parser.init(bytes[0..cut], generous_limits);
        try std.testing.expectError(error.TruncatedRecordHeader, parser.next());
    }
    for (global_header_len + record_header_len..bytes.len) |cut| {
        var parser = try Parser.init(bytes[0..cut], generous_limits);
        try std.testing.expectError(error.TruncatedRecordData, parser.next());
    }
}

test "classic PCAP rejects malformed lengths and timestamps" {
    const valid = try oneRecordCapture(
        std.testing.allocator,
        .little,
        .microseconds,
    );
    defer std.testing.allocator.free(valid);

    var bytes: [global_header_len + record_header_len + 3]u8 = undefined;
    @memcpy(&bytes, valid);

    writeInt(u32, &bytes, global_header_len + 8, 6, .little);
    var captured_larger_than_original = try Parser.init(&bytes, generous_limits);
    try std.testing.expectError(
        error.MalformedRecordLength,
        captured_larger_than_original.next(),
    );

    @memcpy(&bytes, valid);
    writeInt(u32, &bytes, global_header_len + 12, 2, .little);
    var original_too_small = try Parser.init(&bytes, generous_limits);
    try std.testing.expectError(
        error.MalformedRecordLength,
        original_too_small.next(),
    );

    @memcpy(&bytes, valid);
    writeInt(u32, &bytes, global_header_len + 4, 1_000_000, .little);
    var bad_timestamp = try Parser.init(&bytes, generous_limits);
    try std.testing.expectError(error.MalformedTimestamp, bad_timestamp.next());
}

test "classic PCAP distinguishes unsupported and global-header failures" {
    var bytes = [_]u8{0} ** global_header_len;
    try std.testing.expectError(
        error.UnsupportedMagic,
        Parser.init(&bytes, generous_limits),
    );

    @memcpy(bytes[0..4], &magic_little_micro);
    writeInt(u16, &bytes, 4, 1, .little);
    writeInt(u16, &bytes, 6, 0, .little);
    try std.testing.expectError(
        error.UnsupportedVersion,
        Parser.init(&bytes, generous_limits),
    );

    writeInt(u16, &bytes, 4, 2, .little);
    writeInt(u16, &bytes, 6, 4, .little);
    try std.testing.expectError(
        error.MalformedSnaplen,
        Parser.init(&bytes, generous_limits),
    );
}

test "classic PCAP enforces every configured limit" {
    const bytes = try oneRecordCapture(
        std.testing.allocator,
        .little,
        .microseconds,
    );
    defer std.testing.allocator.free(bytes);

    var limits = generous_limits;
    limits.max_snaplen = 127;
    try std.testing.expectError(
        error.SnaplenLimitExceeded,
        Parser.init(bytes, limits),
    );

    limits = generous_limits;
    limits.max_records = 0;
    var record_limited = try Parser.init(bytes, limits);
    try std.testing.expectError(error.RecordLimitExceeded, record_limited.next());

    limits = generous_limits;
    limits.max_capture_bytes = 2;
    var bytes_limited = try Parser.init(bytes, limits);
    try std.testing.expectError(
        error.CaptureBytesLimitExceeded,
        bytes_limited.next(),
    );
}

test "classic PCAP zero-length record policy is explicit" {
    const records = [_]RecordInput{.{
        .timestamp = null,
        .original_len = 0,
        .data = &.{},
    }};
    const bytes = try writeAlloc(std.testing.allocator, .{
        .byte_order = .little,
        .timestamp_resolution = .microseconds,
        .snaplen = 64,
        .link_type = 1,
    }, generous_limits, &records);
    defer std.testing.allocator.free(bytes);

    var allowed = try Parser.init(bytes, generous_limits);
    const record = (try allowed.next()).?;
    try std.testing.expectEqual(@as(usize, 0), record.data.len);

    var reject_limits = generous_limits;
    reject_limits.zero_length_records = .reject;
    var rejected = try Parser.init(bytes, reject_limits);
    try std.testing.expectError(error.ZeroLengthRecordRejected, rejected.next());
    try std.testing.expectError(
        error.ZeroLengthRecordRejected,
        writeAlloc(std.testing.allocator, .{
            .byte_order = .little,
            .timestamp_resolution = .microseconds,
            .snaplen = 64,
            .link_type = 1,
        }, reject_limits, &records),
    );
}

test "classic PCAP writer output is deterministic and preserves metadata" {
    const first = try oneRecordCapture(
        std.testing.allocator,
        .big,
        .nanoseconds,
    );
    defer std.testing.allocator.free(first);
    const second = try oneRecordCapture(
        std.testing.allocator,
        .big,
        .nanoseconds,
    );
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualSlices(u8, first, second);
    try std.testing.expectEqualSlices(u8, &magic_big_nano, first[0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, first[8..12]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, first[12..16]);

    var capture = try Capture.parseAlloc(std.testing.allocator, first, generous_limits);
    defer capture.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), capture.records.len);
    try std.testing.expectEqual(@as(u32, 7), capture.records[0].timestamp.?.seconds);
    try std.testing.expectEqual(@as(u32, 123_456_789), capture.records[0].timestamp.?.fraction);
    try std.testing.expectEqualSlices(u8, &.{ 0xde, 0xad, 0xbe }, capture.records[0].data);
}

test "classic PCAP error classes remain distinct" {
    try std.testing.expectEqual(
        ErrorClass.truncated,
        classifyError(error.TruncatedRecordData),
    );
    try std.testing.expectEqual(
        ErrorClass.malformed,
        classifyError(error.MalformedRecordLength),
    );
    try std.testing.expectEqual(
        ErrorClass.unsupported,
        classifyError(error.UnsupportedMagic),
    );
    try std.testing.expectEqual(
        ErrorClass.limit,
        classifyError(error.RecordLimitExceeded),
    );
    try std.testing.expectEqual(
        ErrorClass.arithmetic,
        classifyError(error.ArithmeticOverflow),
    );
}

fn parseAllocationCase(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var capture = try Capture.parseAlloc(allocator, bytes, generous_limits);
    defer capture.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), capture.records.len);
}

test "owned capture constructor cleans up at every allocation failure" {
    const bytes = try oneRecordCapture(
        std.testing.allocator,
        .little,
        .microseconds,
    );
    defer std.testing.allocator.free(bytes);
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseAllocationCase,
        .{bytes},
    );
}

fn writerAllocationCase(allocator: std.mem.Allocator) !void {
    const bytes = try oneRecordCapture(allocator, .little, .microseconds);
    defer allocator.free(bytes);
    try std.testing.expect(bytes.len > global_header_len);
}

test "capture writer constructor cleans up at every allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        writerAllocationCase,
        .{},
    );
}
