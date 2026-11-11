const std = @import("std");
export fn is_ascii(ptr: [*]const u8, len: usize) bool {
    const bytes = ptr[0..len];
    const width = 32;
    const Bytes = @Vector(width, u8);
    const high_bit: Bytes = @splat(0x80);
    const zero: Bytes = @splat(0);
    var index: usize = 0;
    while (index + width <= bytes.len) : (index += width) {
        const chunk: *align(1) const Bytes = @ptrCast(bytes[index..].ptr);
        if (@reduce(.Or, chunk.* & high_bit != zero)) return false;
    }
    for (bytes[index..]) |byte| if (byte & 0x80 != 0) return false;
    return true;
}
export fn first_zero(ptr: [*]const u8, len: usize) usize {
    return std.mem.findScalar(u8, ptr[0..len], 0) orelse len;
}
