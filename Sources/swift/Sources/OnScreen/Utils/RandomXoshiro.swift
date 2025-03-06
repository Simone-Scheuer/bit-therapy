import Foundation

/// A random number generator using the Xoshiro256** algorithm
struct RandomXoshiro {
    private var state: (UInt64, UInt64, UInt64, UInt64)
    
    init(seed: UInt64) {
        // Initialize the state using SplitMix64 algorithm
        var splitmix = seed
        
        func next() -> UInt64 {
            splitmix &+= 0x9E3779B97F4A7C15
            var z = splitmix
            z = (z ^ (z &>> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z &>> 27)) &* 0x94D049BB133111EB
            return z ^ (z &>> 31)
        }
        
        state = (next(), next(), next(), next())
    }
    
    mutating func next() -> UInt64 {
        let result = rotateLeft(state.1 &* 5, 7) &* 9
        let t = state.1 << 17
        
        state.2 ^= state.0
        state.3 ^= state.1
        state.1 ^= state.2
        state.0 ^= state.3
        
        state.2 ^= t
        state.3 = rotateLeft(state.3, 45)
        
        return result
    }
    
    private func rotateLeft(_ x: UInt64, _ k: UInt64) -> UInt64 {
        return (x << k) | (x >> (64 - k))
    }
} 