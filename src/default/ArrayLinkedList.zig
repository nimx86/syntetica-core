//! Doubly linked indexable linked list

const std = @import("std");

const Allocator = std.mem.Allocator;

/// returns a type which doesn't store it's allocator internally.
pub fn Unmanaged(T: type) type { 
    return struct {
        const ThisUnmanaged = @This();

        /// empty linked list, use as default initializer
        pub const empty = ThisUnmanaged{
            .elements = .empty,
            .links = .empty,
        };

        /// linked list node link
        pub const Link = struct {
            /// previous node
            prev: usize,

            /// next node
            next: usize,
        };

        /// array of elements, reading directly is allowed.
        elements: std.ArrayList(T),

        /// array of links corresponding to the index of each element, 
        /// reading directly is allowed.
        links: std.ArrayList(Link),

        /// root node of the linked list
        root: ?usize = null,

        /// initializes the Linked List with a set starting capacity.
        pub fn initCapacity(gpa: Allocator, num: usize) ThisUnmanaged {
            return .{
                .elements = .initCapacity(gpa, num),
                .links = .initCapacity(gpa, num),
            };
        }

        /// inserts a node at the end of the linked list
        pub fn insertEnd(self: *ThisUnmanaged, node: T) !void {
            if(self.root == null) {
                
            }
        }
    };
}
