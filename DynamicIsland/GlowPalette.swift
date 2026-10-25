import Foundation

/// Glow animation sampled from the wall clock rather than `withAnimation` state.
///
/// Both the outer glow and the inner notch collar derive their values from the same
/// absolute time, so they stay in phase without sharing mutable state, and neither
/// has to restart an animation when the effect or speed changes.
enum GlowPalette {
    /// Degrees of travel of the comet around the island at `date`.
    static func angle(at date: Date, effect: GlowEffect, speed: Double) -> Double {
        guard effect.animates, effect.rotationPeriod > 0 else { return 0 }
        let period = effect.rotationPeriod / max(speed, 0.01)
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        return (t / period) * 360
    }
}
