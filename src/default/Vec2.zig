const std = @import("std");

pub fn PhVec(T: type) type {
    return struct {
        const rad = T;
        const Self = @This();

        direction: rad,
        magnitute: T,

        pub fn val(dir: rad, magn: T) Self {
            return .{.direction = dir, .magnitute = magn};
        }

        pub fn toCaVec(self: Self) Vec2(T) {
            const y = @sin(self.direction) * self.magnitute;
            const x = @sqrt(self.magnitute * self.magnitute - y * y);

            return .val(x, y);
        }
    };
}

/// create a vector type with the fields of it being the value of argument `T`
pub fn Vec2(T: type) type {
    return struct {
        /// coordinate across the x-axis
        x: T,
        /// coordinate across the y-axis
        y: T,

        const Self = @This();

        /// create a vector
        pub fn init(x: T, y: T) Self {
            return .{.x = x, .y = y};
        }

        /// initializes both fields of the vector with a scalar value
        pub fn initScalar(v: T) Self {
            return .{.x = v, .y = v};
        }

        /// depreciated, use .init(...)
        pub fn val(x: T, y: T) Self {
            return .{.x = x, .y = y};
        }

        /// calculates the distance between two points
        pub fn dist(self: Self, b: @TypeOf(Self)) f64 {
            const A = @Vector(2, T){self.x, self.y};
            const B = @Vector(2, T){b.x, b.y};

            const part1 = (A.@"0" - B.@"0") * (A.@"0" - B.@"0");
            const part2 = (A.@"1" - B.@"1") * (A.@"0" - B.@"0");

            return @sqrt(part1 + part2);
        }

        /// adds two vectors together
        pub fn add(self: *Self, b: Self) void {
            self.x += b.x; 
            self.y += b.y;
        }

        /// adds a scalar value to both fields of a vector
        pub fn addScalar(self: *Self, v: T) void {
            self.x += v;
            self.y += v;
        }

        /// subtracts two vectors
        pub fn sub(self: *Self, b: Self) void {
            self.x -= b.x;
            self.y -= b.y;
        }

        /// subtracts a scalar value from both fields of a vector
        pub fn subScalar(self: *Self, v: T) void {
            self.x -= v;
            self.y -= v;
        }

        /// depreciated
        pub fn toPhVec(self: Self) PhVec(T) {
            const magnitute: T = @sqrt(self.x * self.x + self.y * self.y);
            
            const dir = std.math.asin(self.y / magnitute);

            return .{.magnitute = magnitute, .direction = dir};
        }

        /// adds a value to the vector's magnitude
        pub fn addMagnitude(self: *Self, f: T) void {
            // if we have a 0 vector, we don't know in which 
            // direction to add the magnitude.
            if(self.x == 0 and self.y == 0) return;

            // m - magnitude 
            // m1 - new magnitude 
            // U - unit vector 
            // V - resulting vector 
            const m = @sqrt(self.x * self.x + self.y * self.y);

            // this is the part that adds the actual magnitude, the output 
            // is then clamped so it doesn't go below 0
            const m1 = @max(0, m + f);
            const U: Self = .val(self.x / m, self.y / m);

            // this step will flip the signs of the values if needed.
            const V: Self = .val(U.x * m1, U.y * m1);

            self.* = V;
        } 

        /// returns the magnitude of a vector
        pub fn getMagnitude(self: *Self) T {
            return @sqrt(self.x * self.x + self.y * self.y);
        }

        /// sets the magnitude of a vector to a specific value
        pub fn setMagnitude(self: *Self, m: T) void {
            if(self.x == 0 and self.y == 0) return;

            const vec_m = self.getMagnitude();

            const U: Self = .val(self.x / vec_m, self.y / vec_m);

            // this step will flip the signs of the values if needed.
            const V: Self = .val(U.x * m, U.y * m);

            self.* = V;
        }

        /// subtracts a scalar value from the magnitude of a vector
        pub fn subMagnitude(self: *Self, f: T) void {
            self.addMagnitude(-f);
        }

        /// clamps the magnitude of a vector to a specific value
        pub fn clamp(self: *Self, v: T) void {
            if(self.getMagnitude() < v) return;
            self.setMagnitude(v);
        }

        /// rotates a vector by an angle speicifed in radians
        pub fn rotate(self: *Self, point: Self, rad: f32) void {
            const cos = @cos(rad);
            const sin = @sin(rad);

            self.sub(point);

            const newp: Self = .{};
            newp.x = self.x * cos - self.y * sin;
            newp.y = self.x * sin + self.y * cos;

            newp.add(point);
            self = newp;
        }

        /// returns the dot product of a vector
        pub fn dot(self: Self, p2: Self) f32 {
            return self.x * p2.x + self.y * p2.y;
        }
    };
}
