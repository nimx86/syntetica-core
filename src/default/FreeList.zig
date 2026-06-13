//! FreeList implementation for Syntetica Engine.

const std = @import("std");
const QueueList = @import("QueueList.zig");

/// This structure defines a range in the free list
pub const FreeListSlice = struct {
    /// index of the first element of the range
    /// INCLUSIVE
    start: usize,

    /// index of the last element of the range
    /// INCLUSIVE
    end: usize,

    /// size of the range
    /// 1-based. (counting starts from 1)
    size: usize,
};

/// Function for creating a SimpleLinkedFreeList object. SimpleLinkedFreeList is 
/// an implementation of a LinkedList that allows only one element to be asociated 
/// with a memory block instead of multiple as is the case with heap memory.
///
/// @param DataType main type the list will work with.
/// @param alloc_size in how big increments will the list grow.
///                   My recommendation is to check multiple values, higher values 
///                   give a more performant list, but make the list consume more 
///                   memory, while lower values make the list consume less memory, 
///                   but make the list slower.
///
/// @return SimpleLinkedFreeList type, initialize with .init().
///
/// Example:
/// ```Zig 
/// var fl: SimpleLinkedFreeList(TYPE, 200) = ...;
/// // see tests for more exaples.
/// ```
pub fn SimpleLinkedFreeList(DataType: type, alloc_size: usize) type {
    return struct {
        const Self = @This();

        /// metadata struct for data
        const DataMeta = struct {
            prev: usize,
            next: usize,
        };

        /// errors the list can return
        const FreeListError = error {
            element_not_found,
            start_does_not_exist,
            not_initialized,
            list_is_empty,
        };

        /// Data type used for iterating over the SimpleLinkedFreeList.
        /// DO NOT create manually, instead use .createIterator() method.
        pub const Iterator = struct {
            /// free list
            fl: *Self,

            prev_id: usize = 0,
            current_id: usize = 0,
            next_id: usize = 0,
            /// the number of elements that have passed
            count: usize = 0,

            /// if null - use ._start as the iterator start, else 
            /// use the custom_start as the iterator start.
            custom_start: ?usize = null,

            /// inclusive, this id **will** be iterated over.
            end_at: ?usize = null,

            /// Get the next element in the chain. If the reference to the next 
            /// element is desired, use the .nextPtr() function.
            /// NOTE: This function is meant to be used with a
            ///       while loop.
            ///
            /// @param self The iterator.
            ///
            /// @return DataType or null when at the end of the chain
            ///
            /// Example:
            /// ```Zig
            /// // this function is meant to be used inside a while loop
            /// var it = fl.createIterator();
            /// while(it.next()) |data| {
            ///     // ... do something with the data
            /// }
            /// ```
            pub fn next(self: *Iterator) ?DataType {
                return if(self.nextPtr()) |val| val.* else null;
            }

            /// Get the pointer to the next element in the chain.
            /// NOTE: This function is meant to be used with a
            ///       while loop.
            ///
            /// @param self The iterator 
            ///
            /// @return Datatype pointer or null when at the end of the chain
            ///
            /// Example:
            /// ```Zig
            /// var it = fl.createIterator();
            /// while(it.nextPtr()) |data| {
            ///     // ... do something with the data pointer
            /// }
            /// ```
            pub fn nextPtr(self: *Iterator) ?*DataType {
                self.current_id = self.next_id;

                self.next_id = self.fl._data_info[self.current_id].next;
                self.prev_id = self.fl._data_info[self.current_id].prev;

                // check if we reached the end at value, it shouldn't end exactly at that 
                // value, but after it passes it, so we check if the value before was the 
                // wanted value, but if the slice we are iterating over is the only slice,
                // we would make this end prematurely, so we check if we had at least one 
                // iteration.
                const check_should_end = 
                    if(self.end_at != null)
                        // last node was the node we should end at and we had at least 
                        // one iteration
                        self.prev_id == self.end_at.? and self.count != 0 
                    else false;
                const ret = 
                    if(self.count == self.fl._occupied or check_should_end) 
                        null 
                    else 
                        @as(?*DataType, &self.fl.data[self.current_id]);

                self.count += 1;

                return ret;
            }

            /// Make the next id be a custom value.
            ///
            /// @param self The Iterator.
            /// @param id The id of the next node.
            ///
            /// @return void.
            pub fn changeNext(self: *Iterator, id: usize) void {
                self.next_id = id;
            }

            /// Returns the pointer to the data at the current id.
            ///
            /// @param self The iterator.
            /// 
            /// @return pointer to current data.
            pub fn getPtr(self: *Iterator) *DataType {
                return &self.fl.data[self.current_id];
            }

            /// Resets the iterator to initial values 
            ///
            /// @param self The iterator.
            ///
            /// @return void or error if the list is empty.
            pub fn reset(self: *Iterator) FreeListError!void {
                self.count = 0;
                const start = self.custom_start orelse self.fl._start;
                self.next_id = start orelse 
                    return FreeListError.start_does_not_exist;
                self.current_id = 0;
            }
        };

        /// used for keeping track if the FreeList is initialized
        _initialized: bool = false,

        /// elements array
        data: []DataType = undefined,

        /// metadata for elements
        _data_info: []DataMeta = undefined,

        /// array of available elements
        _free_space: []?usize = undefined,
        
        /// First element of the linked list
        _start: ?usize = null,

        /// keeps track of how many IDs are occupied inside the list
        _occupied: usize = 0,

        /// used for easier iterating over the freelist
        /// DEPRECEATED - use Iterator
        _compact_list: []usize = &[0]usize{},

        /// allocator
        allocator: std.mem.Allocator = undefined,

        /// Intenal function, marks the next id as taken and returns it, increments the 
        /// occupied tracker
        ///
        /// @param self The FreeList.
        ///
        /// @return taken ID
        fn takeID(self: *Self) usize {
            const id = self._free_space[self.data.len - self._occupied - 1] orelse unreachable;
            self._free_space[self.data.len - self._occupied - 1] = null;
            self._occupied += 1;

            return id;
        }

        /// Internal function, marks the give ID as available, decrements the 
        /// occupied tracker
        ///
        /// @param self The FreeList
        /// @param id the ID to mark as available 
        ///
        /// @return void
        fn giveID(self: *Self, id: usize) void {
            self._free_space[self.data.len - self._occupied] = id;
            self._occupied -= 1;
        }

        /// Internal function used for checking the size of the internal 
        /// data, _data_info and _free_space arrays.
        ///
        /// @param self the FreeList.
        /// @return error if the allocation fails.
        fn checkAndResize(self: *Self) !void {
            // if we can fit more elements (num of occupied is not more than data lenght), then
            // just return and don't resize anything
            if(!(self._occupied >= self.data.len)) return;

            self.data = 
                try self.allocator.realloc(self.data, self.data.len + alloc_size);

            self._data_info = 
                try self.allocator.realloc(self._data_info, self._data_info.len + alloc_size);

            self._free_space = 
                try self.allocator.realloc(self._free_space, self._free_space.len + alloc_size);

            // insert the IDs into the available IDs list
            for(self._free_space, 1..) |*data, i| {
                data.* = self._free_space.len - i;
            }
        }

        /// Internal function that does the same this as checkAndResize, but for multiple
        /// elements. Instead of checking if a single element will fit, it checks if 
        /// N-amount of elements will fit (and resizes)
        ///
        /// @param self the FreeList.
        /// @param n the amount of elements to check for.
        ///
        /// @return error if the allocation fails.
        fn checkAndResizeN(self: *Self, n: usize) !void {
            // check if the new elements would fit
            if(!(self._occupied >= self.data.len + n)) return;

            // normally, we'd do only alloc_size for one element, 
            // but we are allocating for N elements, so we multiply 
            // the alloc_size.
            const new_size = alloc_size * n;

            self.data = 
                try self.allocator.realloc(self.data, self.data.len + new_size);

            self._data_info = 
                try self.allocator.realloc(self._data_info, self._data_info.len + new_size);

            self._free_space = 
                try self.allocator.realloc(self._free_space, self._free_space.len + new_size);

            // insert the IDs into the available IDs list
            for(self._free_space, 1..) |*data, i| {
                data.* = self._free_space.len - i;
            }
        }

        /// Internal function for linking an id to the chain.
        ///
        /// @param self the FreeList.
        /// @param id the id to link.
        ///
        /// @return none.
        fn link(self: *Self, id: usize) void {
            if(self._start == null) {
                self._start = id;
                self._data_info[id].prev = id;
                self._data_info[id].next = id;
            } else {
                // set our last to root's last
                self._data_info[id].prev = self._data_info[ self._start.? ].prev;

                // set ourselves as root's last
                self._data_info[self._start.?].prev = id;

                // set our next to root
                self._data_info[id].next = self._start.?; 

                // set ourselves as our new previous' next
                self._data_info[self._data_info[id].prev].next = id; 
            }
        }

        /// Initialize the SimpleLinkedFreeList type with an allocator of choice
        ///
        /// @param allocator std.mem.Allocator of choice
        ///
        /// @return SimpleLinkedFreeList or error if init fails.
        ///
        /// Example:
        /// ```Zig 
        /// var fl: SimpleLinkedFreeList(TYPE, 200) = .init(ALLOCATOR_OF_CHOICE);
        /// // ... do something with fl
        /// ```
        pub fn init(allocator: std.mem.Allocator) !Self {
            var obj: Self = .{};

            obj.allocator = allocator;

            obj.data = try obj.allocator.alloc(DataType, alloc_size);
            obj._data_info = try obj.allocator.alloc(DataMeta, alloc_size);
            obj._free_space = try obj.allocator.alloc(?usize, alloc_size);
            
            // I'm not too sure about allocating 0 bytes, but that memory won't be used anyway,
            // and it seems to grow fine. Maybe find a way to make this work safer in the future.
            obj._compact_list = try obj.allocator.alloc(usize, 0); 

            for(obj._free_space, 0..) |*data, i| {
                data.* = alloc_size - i - 1;
            }

            obj._initialized = true;
            return obj;
        }

        /// Returns the index a value would be inserted at without inserting anything. The 
        /// Index becomes invalid as soon as a new value is inserted into the free list.
        ///
        /// @param self The FreeList.
        ///
        /// @return insertion index.
        ///
        /// Example:
        /// ```Zig 
        /// var fl: ... = ...;
        /// const id = fl.peekInsertionIndex();
        /// const id1 = fl.insert(A);
        /// // id == id1 here.
        /// ```
        pub fn peekInsertionIndex(self: *Self) usize {
            return self._free_space[self.data.len - self._occupied - 1] orelse unreachable;
        }

        pub fn reserve(self: *Self) !usize {
            std.debug.assert(self._initialized == true);

            try self.checkAndResize();
            const id = self.takeID();
            self.link(id);

            return id;
        }

        /// Inserts new value into the SimpleLinkedFreeList. The inserted id stays valid
        /// until it's removed from the list using .deleteID(), after which, accessing
        /// it is UB (you will get junk data).
        ///
        /// @param self the FreeList.
        /// @param data the object to insert.
        ///
        /// @return index of the inserted object or error if the insertion fails.
        ///
        /// Example:
        /// ```Zig 
        /// var fl: ... = ...;
        /// const id = fl.insert(OBJECT);
        /// ```
        pub fn insert(self: *Self, data: DataType) !usize {
            if(self._initialized == false) return FreeListError.not_initialized;
            try self.checkAndResize();

            const id = self.takeID();
            self.link(id);

            // assign the data to the reserved ID
            self.data[id] = data;

            return id;
        }

        /// inserts a slice of FreeList's type as individual elements, linked together,
        /// performs size check once, thus a bit efficient than just using insert for 
        /// every element, especially when adding a lot of elements. Remove the added
        /// slice either individually, or using .deleteSlice(...).
        /// 
        /// @param self the FreeList.
        /// @param slice the slice to insert. 
        ///
        /// @return FreeListSlice containing the first and the last element
        ///
        /// Example:
        /// ```Zig 
        /// var fl: SimpleLinkedFreeList(u8, 50) = .init(ALLOCATOR);
        /// const fl_slice = fl.insertSlice(&.{3, 5, 6, 2, 6});
        /// // check out the type FreeListSlice.
        /// ```
        pub fn insertSlice(self: *Self, slice: []const DataType) !FreeListSlice {
            if(self._initialized == false) return FreeListError.not_initialized;
            try self.checkAndResizeN(slice.len - 1);

            const start = self.takeID();

            self.data[start] = slice[0];

            self.link(start);

            // edge case where we add a slice to a list containing 0 elements.
            if(self._start == null) self._start = start;

            var end: usize = 0;
            for(slice[1..]) |data| {
                const id = self.takeID();

                self.link(id);

                self.data[id] = data;
                end = id;
            }

            return .{
                .start = start,
                .end = end,
                .size = slice.len,
            };
        }

        /// Removes a FreeListSlice from the FreeList
        ///
        /// @param self The FreeList
        /// @param slice The slice to remove 
        ///
        /// @return void or error if the list is empty.
        ///
        /// Example:
        /// ```
        /// var fl: ... = ...;
        /// const s = try fl.insertSlice(&.{a, b, c, d, e, f});
        /// try fl.deleteSlice(s);
        /// ```
        pub fn deleteSlice(self: *Self, slice: FreeListSlice) FreeListError!void {
            // check if the start even exists
            const start = self._start orelse return FreeListError.start_does_not_exist; 

            // check if the slice has a root node
            var slice_root: ?usize = null; // if null - no root
            var it = try self.createSliceIterator(slice); // create a slice iterator
            while(it.next()) |_| {
                // if there's a root node, assign the slice_root var accordingly
                if(it.current_id == start){ 
                    slice_root = it.current_id;
                }

                self.giveID(it.current_id);
            }

            // slice's previous and next nodes
            const next_id = self._data_info[slice.end].next;
            const prev_id = self._data_info[slice.start].prev;

            // if our slice doesn't contain a root node, we can 
            // just unlink it normally.
            if(slice_root == null) {
                self._data_info[prev_id].next = next_id;
                self._data_info[next_id].prev = prev_id;
            } else { // but if it does contain a root node.
                // check if we are removing the last nodes
                if(self._occupied <= 1) {
                    self._start = null;
                    return;
                }

                // set the root to the slice's next node.
                self._start = next_id;

                // set the previous node's next to the chain's next
                self._data_info[prev_id].next = next_id;

                // set the next node's previous to the chain's previous
                self._data_info[next_id].prev = prev_id;
            }
        }

        /// Deletes an ID from SimpleLinkedFreeList, use this when you are done with 
        /// using a place in the SimpleLinkedFreeList. Note that the deleted ID is 
        /// still accessible through .get() function, but it will get overwritten when 
        /// requesting another id.
        ///
        /// @param self The freelist.
        /// @param id The id to delete.
        ///
        /// @return void
        pub fn deleteID(self: *Self, id: usize) void {
            // handle edge case when deleting a root node which is also last
            if(self._start == id and self._occupied <= 1) {
                self._start = null;
            } else {
                // remove the element from linked list
                self._data_info[self._data_info[id].prev].next = self._data_info[id].next; // our previous' next = our next
                self._data_info[self._data_info[id].next].prev = self._data_info[id].prev; // our next's previous = our previous
                
                if(self._start == id) { // if the node we are trying to delete is root
                    self._start = self._data_info[id].next; // our next node becomes the root
                }
            }

            self.giveID(id);
        }

        /// Returns the data stored at a specified ID
        ///
        /// @param self The FreeList.
        /// @param id The id to get.
        ///
        /// @return Data at the index
        pub fn get(self: *Self, id: usize) DataType {
            return self.data[id];
        }

        /// Returns the pointer to the data stored at a specified ID
        ///
        /// @param self The FreeList.
        /// @param id The id to get the pointer 
        ///
        /// @return Pointer to the data at the index.
        pub fn getPtr(self: *Self, id: usize) *DataType {
            return &self.data[id];
        }

        /// Return all elements of the SimpleLinkedFreeList as an iterable (and unsorted) array.
        /// Can return error if allocation for the iterable array fails. This is depreciated,
        /// use the Iterator instead.
        ///
        /// @param self The FreeList.
        /// 
        /// @return slice of indexes in order of linking.
        pub fn listIDs(self: *Self) ![]usize {
            if(self._compact_list.len == self._occupied) return self._compact_list; 

            self._compact_list = try self.allocator.realloc(self._compact_list, self._occupied);

            var current_id: usize = self._start orelse return FreeListError.start_does_not_exist;
            for(self._compact_list) |*index| {
                index.* = current_id;
                current_id = self._data_info[current_id].next;
            }

            return self._compact_list;
        }

        /// Create an iterator object.
        ///
        /// @param self The FreeList.
        /// 
        /// @return Iterator or error if the list is empty
        ///
        /// Example:
        /// ```Zig 
        /// var fl: ... = ...;
        /// var it = try fl.createIterator();
        /// while(it.next()) |data| {
        ///     // use it.getPtr() to get the pointer to the current id.
        ///     // ... do something with data.
        /// } 
        /// ```
        pub fn createIterator(self: *Self) FreeListError!Iterator {
            if(self._occupied == 0) return FreeListError.list_is_empty;

            return .{
                .fl = self,
                .next_id = self._start orelse return FreeListError.start_does_not_exist,
            };
        }

        /// Create a slice iterator
        ///
        /// @param self The FreeList.
        /// @param slice The slice to iterate over 
        ///
        /// @return Iterator or error if the list is empty 
        ///
        /// Example:
        /// ```Zig 
        /// var fl: ... = ...;
        /// const s = fl.insertSlice(&.{a, b, c, d});
        ///
        /// var it = fl.createSliceIterator(s);
        /// while(it.next()) |data| {
        ///     // check out .createIterator().
        ///     // ... do something with data.
        /// }
        /// ```
        pub fn createSliceIterator(self: *Self, slice: FreeListSlice) FreeListError!Iterator {
            if(self._occupied == 0) return FreeListError.list_is_empty;

            return .{
                .fl = self,
                .next_id = slice.start,
                .custom_start = slice.start,
                .end_at = slice.end,
            };
        }

        /// Finds a needle in the FreeList, O(n).
        ///
        /// @param self The freelist.
        /// @param cmp_data The needle to find.
        ///
        /// @return index of the needle or error if it can't be found
        pub fn find(self: *Self, cmp_data: DataType) FreeListError!usize {
            var it = try self.createIterator();
            for(it.next()) |data| {
                if(std.meta.eql(data, cmp_data)) return it.current_id;
            }
            return FreeListError.element_not_found;
        }

        /// wrapper for legacy support, if possible, replace all instances
        /// of this function with deinit()
        pub fn release(self: *Self) void {
            self.deinit();
        }

        /// deinit the FreeList, call when done.
        ///
        /// @param self The freelist.
        ///
        /// @return void
        ///
        /// Example:
        /// ```
        /// const fl: ... = ...;
        /// defer fl.deinit();
        /// ```
        pub fn deinit(self: *Self) void {
            if(self._initialized == false) return;

            self.allocator.free(self.data);
            self.allocator.free(self._data_info);
            self.allocator.free(self._free_space);
            self.allocator.free(self._compact_list);
            self._initialized = false;
        }
    };
}

pub fn ManyTypeLinkedFreeList(alloc_size: usize) type {
    return struct {
        const Self = @This();
        pub fn ListID(T: type) type {
            return struct {
                pub const Type = T;
                start: usize = 0,
                size: usize = 0,
            };
        }

        const Occupant = struct {
            /// queue of IDs
            free: QueueList.QueueLIFO(usize, alloc_size),
        };

        allocator: std.mem.Allocator,
        
        /// the actual data is stored as a simple array of bytes
        data: []u8,

        occupied: usize = 0,
        free_space: std.AutoHashMap(usize, Occupant),
        links: std.DoublyLinkedList = undefined,

        fn ensureEnoughCapacity(self: *Self, size: usize) !void {
            if(self.occupied + size <= self.data.len) return; // enough capacity 
            
            // this formula figures out the required size for n-amount of bytes
            const new_size = (@divTrunc(self.occupied + size, alloc_size) + 1) * alloc_size;
            self.data = try self.allocator.realloc(self.data, new_size);
        }

        fn validateIDType(T: type) void {
            comptime {
                if(!@hasField(T, "start")) 
                    @compileError("ListID type must have start field")
                else if(@FieldType(T, "start") != usize) 
                    @compileError("ListID's field \"start\" must be of type usize")
                
                else if(!@hasField(T, "size")) 
                    @compileError("ListID type must have size field")
                else if(@FieldType(T, "size") != usize) 
                    @compileError("ListID's field \"size\" must be of type usize")

                else if(!@hasDecl(T, "Type"))
                    @compileError("ListID type must have a declaration of the type it represents.");
            }
        }

        pub fn printMemInfo(self: *Self) void {
            std.debug.print("--------- DUMP START ---------\n", .{});

            std.debug.print("DATA: ", .{});
            for (self.data) |value| {
                std.debug.print("{X:02} ", .{value});
            }
            std.debug.print("\n", .{});

            std.debug.print("MAP: \n", .{});
            var it = self.free_space.iterator();
            while(it.next()) |entry| {
                std.debug.print("  SIZE: {} -> ", .{entry.key_ptr.*});
                for(entry.value_ptr.free.data[0..entry.value_ptr.free._occupied]) |id| {
                    std.debug.print("{} ", .{id});
                }
                std.debug.print("\n", .{});
            }

            std.debug.print("---------- DUMP END ----------\n", .{});
        }
        
        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .allocator = allocator,
                .data = try allocator.alloc(u8, alloc_size),
                .free_space = .init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.free_space.iterator();
            while(it.next()) |entry| {
                entry.value_ptr.free.deinit();
            }
            self.free_space.deinit();
            self.allocator.free(self.data);
        }

        pub fn insert(self: *Self, comptime data: anytype) !ListID(@TypeOf(data)) {
            const data_size = @sizeOf(@TypeOf(data));

            const occupant = self.free_space.getPtr(data_size);

            // check if there's space already available for this size
            var id: usize = 0;
            if(occupant != null and occupant.?.free._occupied > 0) {
                id = try occupant.?.free.take();
            } else { // if not, allocate new andor append to the unused space
                try self.ensureEnoughCapacity(data_size);
                id = self.occupied;
            }

            self.occupied += data_size;

            std.debug.print("recieved ID: {}\n", .{id});

            var data_bytes_slice: []const u8 = @ptrCast(&data);
            data_bytes_slice.len = data_size;

            // copy the bytes over to the data array
            @memcpy(self.data[id..id + data_size], data_bytes_slice);

            return ListID(@TypeOf(data)){
                .start = id,
                .size = data_size,
            };
        }

        pub fn reserveBytes(self: *Self, amount_of_bytes: usize) !ListID(void) {
            const data_size = amount_of_bytes;

            const occupant = self.free_space.getPtr(data_size);

            // check if there's space already available for this size
            var id: usize = 0;
            if(occupant != null and occupant.?.free._occupied > 0) {
                id = try occupant.?.free.take();
            } else { // if not, allocate new andor append to the unused space
                try self.ensureEnoughCapacity(data_size);
                id = self.occupied;
            }

            self.occupied += data_size;

            return ListID(void){
                .start = id,
                .size = data_size,
            };
        }

        pub fn insertSlice() !FreeListSlice {}

        pub fn deleteID(self: *Self, id: anytype) !void {
            comptime validateIDType(@TypeOf(id));

            if(self.free_space.getPtr(id.size)) |val| {
                _ = try val.free.insert(id.start);
            } else {
                var occ: Occupant = .{.free = undefined};
                occ.free = try @TypeOf(occ.free).init(self.allocator);
                _ = try occ.free.insert(id.start);
                try self.free_space.put(id.size, occ);
            }
            self.occupied -= id.size;
        }

        pub fn deleteSlice() !void {}

        pub fn get(self: *Self, id: anytype) @TypeOf(id).Type {
            return self.getPtr(id).*;
        }

        pub fn getPtr(self: *Self, id: anytype) *@TypeOf(id).Type {
            comptime validateIDType(@TypeOf(id));

            var bytes: []u8 = self.data[id.start..];
            bytes.len = id.size;

            const cast_type_ptr: *@TypeOf(id).Type = @alignCast(@ptrCast(bytes));
            return cast_type_ptr;
        }
    };
}

const Allocator = std.mem.Allocator;

pub const Simple = struct {
    // make this the defacto implementation
};

pub const SimpleLinked = struct {
    pub fn Unmanaged(T: type) type {
        return struct {
            const ThisUnmanaged = @This();
            const Index = usize;

            pub const Link = struct {
                next: Index,
                prev: Index,
            };

            /// iterator struct for the Unmanaged Simple Linked list.
            /// bad practice to create manually, use `.iterator()`.
            pub const Iterator = struct {
                /// actual list
                list: *SimpleLinked.Unmanaged(T),

                /// tracks the current item
                current: usize,
                passed: usize = 0,

                /// get the current item's pointer and advance to the next item.
                pub fn nextPtr(it: *Iterator) ?*T {
                    if(it.list.root == null) return null;

                    defer { 
                        it.current = it.list.links[it.current].next;
                        it.passed += 1;
                    }

                    // return the current value unless we had a loop and the current 
                    // node is root, in which case return null.
                    return if(it.current == it.list.root.? and it.passed > 0) 
                        null else &it.list.data[it.current];
                }

                /// get the current item and advance to the next.
                pub fn next(it: *Iterator) ?T {
                    return if(it.nextPtr()) |v| v.* else null;
                }

                /// reset the iterator
                pub fn reset(it: *Iterator) void {
                    it.current = it.list.root.?;
                }
            };
            
            /// DO NOT USE.
            /// Meant exclusively for use as a placeholder
            var emptyarr = [0]T{};

            /// the list is guarantied to be usable after being set 
            /// to this state
            pub const empty: Unmanaged(T) = .{
                .data = &emptyarr,
                .links = undefined,
                .free_index = undefined,
                .occupied = 0,
                .root = null,
            };

            /// data array, stores the actual data.
            data: []T, // usize + usize

            /// link array, the size of this array is that of the 
            /// data array.
            links: [*]Link, // usize 

            /// list of free indexes, the size of this array is that of the 
            /// data array.
            free_index: [*]Index, // usize

            /// keeps track of how much of each array is actually occupied.
            occupied: usize = 0, // usize

            /// keeps track of the root node of the chain.
            root: ?Index = null, // usize + usize 

            const init_capacity = 
                @as(comptime_int, @max(1, std.atomic.cache_line / @sizeOf(T)));

            /// Called when memory growth is necessary. Returns a capacity larger than
            /// minimum that grows super-linearly.
            ///
            /// shamelessly stolen from std.array_list.Aligned(...)
            fn growCapacity(current: usize, minimum: usize) usize {
                var new = current;
                while (true) {
                    new +|= new / 2 + init_capacity;
                    if (new >= minimum) return new;
                }
            }

            /// populates the free index array from the start of the array to the `data.len - occupied`
            /// with numbers from (and including) `start` argument. Should be ran only when all of the 
            /// available indices are exhausted.
            inline fn populateFreeIndices(self: *ThisUnmanaged, start: usize) void {
                for(self.free_index[0..self.data.len - self.occupied], start..) |*index_space, i|
                    index_space.* = i;
                std.debug.print("POPULATING: {any}\n", .{self.free_index[0..self.data.len]});
            }

            /// ensure all of the internal arrays can fit the data they need to fit.
            fn ensureEnoughCapacity(self: *ThisUnmanaged, gpa: Allocator) !void {
                if(self.occupied < self.data.len) return;

                // allocated space == 0 means it hasn't been initialized yet.
                if(self.data.len == 0) {
                    // initialize each list
                    self.data = try gpa.alloc(T, init_capacity);
                    self.links = (try gpa.alloc(Link, init_capacity)).ptr;
                    self.free_index = (try gpa.alloc(Index, init_capacity)).ptr;

                    // make sure to populate the index array.
                    self.populateFreeIndices(0);

                    // we have enough space, return 
                    return;
                }

                // grow all the arrays 
                const grow_by = growCapacity(self.data.len, self.data.len + 1);
                const first_index = self.data.len;

                self.links = (try gpa.realloc(self.links[0..self.data.len], grow_by)).ptr;
                self.free_index = (try gpa.realloc(self.free_index[0..self.data.len], grow_by)).ptr;

                // needs to be resized last, since the size of this array is used as a reference
                // to other arrays and once it's resized before other arrays, the size doesn't match
                // anymore.
                self.data = try gpa.realloc(self.data, grow_by);

                // populate indices starting from the first available index.
                self.populateFreeIndices(first_index);
            }

            /// gets the next available index
            inline fn peekIndex(self: *ThisUnmanaged) Index {
                // `self.data.len - self.occupied - 1` is how we get the first index available of the 
                // index array.
                return self.free_index[self.data.len - self.occupied - 1];
            }

            /// links an index to the end of the chain, so the root's last index becomes the index `i`
            fn linkIndex(self: *ThisUnmanaged, i: Index) void {
                // in case this is the first node, we need to set it as root
                if(self.root == null) {
                    self.root = i;

                    // root is just linked to itself
                    self.links[i].prev = i;
                    self.links[i].next = i;

                    return;
                } 
                // set our last to root's last
                self.links[i].prev = self.links[ self.root.? ].prev;

                // set ourselves as root's last
                self.links[self.root.?].prev = i;

                // set our next to root
                self.links[i].next = self.root.?; 

                // set ourselves as our new previous' next
                self.links[self.links[i].prev].next = i;
            }

            /// unlinks the supplied index from the linked list
            fn unlinkIndex(self: *ThisUnmanaged, i: Index) void {
                // alias
                const previous = self.links[i].prev;
                const next = self.links[i].next;

                // set our previous' next to be our next
                self.links[previous].next = next;

                // set our next's prevous to be our previous
                self.links[next].prev = previous;
            }

            pub fn dumpMemory(self: ThisUnmanaged) void {
                std.debug.print("------------ MEM DUMP -------------------------\n", .{});
                std.debug.print("root is: {?}\n", .{self.root});
                std.debug.print("occupied: {}\n", .{self.occupied});
                std.debug.print("DATA: << {any} >>\n", .{self.data});
                std.debug.print("LINKS: << {any} >>\n", .{self.links[0..self.data.len]});
                std.debug.print("AVAILABLE: << {any} >>\n", .{self.free_index[0..self.data.len]});

                var index = self.root.?;
                while(true) : ({index = self.links[index].next; if(index == self.root.?) break;}) {
                    std.debug.print("[i:{};v:{}] -> ", .{index, self.data[index]});

                }
                std.debug.print("\n", .{});
                std.debug.print("------------ END DUMP -------------------------\n", .{});
            }

            /// Reserves an index for use without puting anything in it's data space.
            pub fn reserve(self: *ThisUnmanaged, gpa: Allocator) !Index {
                try self.ensureEnoughCapacity(gpa);
                const i = self.peekIndex();

                // make sure to increment the occupied counter
                self.occupied += 1;
                self.linkIndex(i);

                return i;
            }

            /// gets the pointer to an element at index `i`
            pub inline fn getPtr(self: ThisUnmanaged, i: Index) *T {
                return &self.data[i];
            }

            /// get the value at index `i`
            pub inline fn get(self: ThisUnmanaged, i: Index) T {
                return self.data[i];
            }

            /// Retrieves the last element's index. 
            /// Asserts that the root is not null.
            pub fn getLastElementIndex(self: ThisUnmanaged) usize {
                std.debug.assert(self.root != null);
                
                return self.links[self.root.?].prev;
            }

            /// retrives the last element's pointer.
            /// Asserts that the root is not null.
            pub fn getLastElementPtr(self: ThisUnmanaged) *T {
                return &self.data[ self.getLastElementIndex() ];
            }

            /// returns the pointer to the root node, 
            /// asserts the root node is not null.
            pub fn getRootPtr(self: ThisUnmanaged) *T {
                std.debug.assert(self.root != null);

                return &self.data[ self.root.? ];
            }

            /// Inserts an element into the list
            pub fn insert(self: *ThisUnmanaged, gpa: Allocator, data: T) !Index {
                const i = try self.reserve(gpa);

                self.getPtr(i).* = data;

                return i;
            }

            /// remove an index from the list
            pub fn remove(self: *ThisUnmanaged, index: usize) void {
                // return the index to the respective array
                self.free_index[self.data.len - self.occupied] = index;

                // decrement the occupied counter
                self.occupied -= 1;

                // the removal of a root node must have special handling
                if(index == self.root.?) self.root = self.links[index].next;
                self.unlinkIndex(index);
            }

            /// create a new iterator, use with while loop.
            pub fn iterator(self: *ThisUnmanaged) ThisUnmanaged.Iterator {
                return .{
                    .list = self,
                    .current = self.root orelse 0,
                };
            }

            /// deinits the list
            pub fn deinit(self: *ThisUnmanaged, gpa: Allocator) void {
                gpa.free(self.data);
                gpa.free(self.links[0..self.data.len]);
                gpa.free(self.free_index[0..self.data.len]);
            }
        };
    }

    pub fn Managed(T: type) type {
        return struct {
            const ThisManaged = @This();
            const Unman = SimpleLinked.Unmanaged(T);

            const empty: ThisManaged = .{ 
                .allocator = undefined,
                .unmanaged = .empty,
            };

            unmanaged: Unman,
            allocator: Allocator,

            pub fn init(gpa: Allocator) ThisManaged {
                return .{
                    .unmanaged = .empty,
                    .allocator = gpa,
                };
            }

            pub inline fn reserve(self: *ThisManaged) !Unman.Index {
                return self.unmanaged.reserve(self.allocator);
            }

            pub inline fn getPtr(self: *ThisManaged, i: Unman.Index) *T {
                return self.unmanaged.getPtr(i);
            }

            pub inline fn insert(self: *ThisManaged, v: T) !Unman.Index {
                return self.unmanaged.insert(self.allocator, v);
            }

            pub inline fn remove(self: *ThisManaged, index: usize) void {
                return self.unmanaged.remove(index);
            }

            pub inline fn iterator(self: *ThisManaged) Unman.Iterator {
                return self.unmanaged.iterator();
            }

            pub inline fn deinit(self: *ThisManaged) void {
                self.unmanaged.deinit(self.allocator);
            }
        };
    }
};

const freelist = @This();
const testing = std.testing;
const testing_alloc_size = 20;

test "SimpleLinked.Unmanaged.insert" {
    var fl: SimpleLinked.Unmanaged(u8) = .empty;
    defer fl.deinit(testing.allocator);

    const i = try fl.insert(testing.allocator, 7);
    _ = try fl.insert(testing.allocator, 18);
    _ = try fl.insert(testing.allocator, 20);

    for(0..125) |n| {
        _ = try fl.insert(testing.allocator, @as(u8, @intCast(n)) + 2);
    }

    fl.remove(25);

    _ = try fl.insert(testing.allocator, 67);
    std.debug.print("index: {}\n", .{i});
    std.debug.print("size = {}\n", .{@sizeOf(usize)});
    std.debug.print("@sizeOf(fl) = {};\n", .{@sizeOf(SimpleLinked.Unmanaged(u8))});

    std.debug.print("VALUES: ", .{});
    var it = fl.iterator();
    while(it.next()) |v| {
        std.debug.print("{} ", .{v});
    }
    std.debug.print("\n", .{});

    fl.dumpMemory();
}

const FL = SimpleLinkedFreeList(u8, testing_alloc_size);

//
// test "FreeListSlice(types)" {
//     // check if the slice is big enough to hold indexes
//     const foo = FreeListSlice{};
//     try testing.expectEqual(usize, @TypeOf(foo.start));
//     try testing.expectEqual(usize, @TypeOf(foo.end));
//     try testing.expectEqual(usize, @TypeOf(foo.size));
// }
//
// test "SimpleLinkedFreeList.init" {
//     var fl = try FL.init(testing.allocator);
//     defer fl.release();
//
//     try testing.expectEqual(testing_alloc_size, fl.data.len);
//     try testing.expectEqual(testing_alloc_size, fl._data_info.len);
//     try testing.expectEqual(testing_alloc_size, fl._free_space.len);
//     try testing.expectEqual(true, fl._initialized);
//     try testing.expectEqual(null, fl._start);
//     try testing.expectEqual(0, fl._occupied);
//
//     for (fl._free_space, 0..) |value, i| {
//         try testing.expectEqual(testing_alloc_size - i - 1, value);
//     }
// }
//
// test "SimpleLinkedFreeList.createIterator" {
//     var fl = try FL.init(testing.allocator);
//     defer fl.release();
//
//     // free list should return an error for no elements
//     try testing.expectError(error.list_is_empty, fl.createIterator());
//
//     _ = try fl.insert(5);
//
//     var it = try fl.createIterator();
//     _ = &it;
//
//     try testing.expectEqual(it.next_id, fl._start);
// }
//
// test "SimpleLinkedFreeList.createSliceIterator" {
//     var fl = try FL.init(testing.allocator);
//     defer fl.release();
//
//     _ = try fl.insert(0);
//     _ = try fl.insert(0);
//
//     const s = try fl.insertSlice(&.{5, 0, 6, 0xFF});
//     var it = try fl.createSliceIterator(s);
//
//     _ = try fl.insert(0);
//     _ = try fl.insert(0);
//
//     try testing.expectEqual(@as(?u8, 5), it.next());
//     try testing.expectEqual(@as(?u8, 0), it.next());
//     try testing.expectEqual(@as(?u8, 6), it.next());
//     try testing.expectEqual(@as(?u8, 0xFF), it.next());
//     try testing.expectEqual(@as(?u8, null), it.next());
// }
//
// test "SimpleLinkedFreeList.Iterator.next" {
//     var fl = try FL.init(testing.allocator);
//     defer fl.release();
//
//     _ = try fl.insert(5);
//     _ = try fl.insert(4);
//     _ = try fl.insert(2);
//     _ = try fl.insert(0xFF);
//
//     var it = try fl.createIterator();
//
//     try testing.expectEqual(@as(?u8, 5), it.next());
//     try testing.expectEqual(@as(?u8, 4), it.next());
//     try testing.expectEqual(@as(?u8, 2), it.next());
//     try testing.expectEqual(@as(?u8, 0xFF), it.next());
//     try testing.expectEqual(@as(?u8, null), it.next());
// }
//
// test "SimpleLinkedFreeList.Iterator.reset" {
//     var fl = try FL.init(testing.allocator);
//     defer fl.release();
//
//     _ = try fl.insert(5);
//     const id1 = try fl.insert(4);
//
//     var it = try fl.createIterator();
//
//     _ = it.next();
//     _ = it.next();
//     _ = it.next();
//
//     try it.reset();
//
//     try testing.expectEqual(0, it.count);
//     try testing.expectEqual(it.fl._start, it.next_id);
//     try testing.expectEqual(0, it.current_id);
//
//     it.custom_start = @intCast(id1);
//     try it.reset();
//     _ = it.next();
//
//     try testing.expectEqual(it.custom_start, it.current_id);
// }
//
// test "SimpleLinkedFreeList.insertSlice" { 
//     var fl = try FL.init(testing.allocator);
//     defer fl.release();
//
//     _ = try fl.insert(5);
//     const s = try fl.insertSlice(&.{4, 5, 2, 6});
//
//     try testing.expectEqual(1, s.start);
//     try testing.expectEqual(4, s.end);
//     try testing.expectEqual(4, s.size);
// }
