import Foundation

/// The One Euro filter (Casiez, Roussel, Vogel 2012): low jitter when the hand is still,
/// low lag when it moves. The standard choice for pointer smoothing from noisy trackers.
struct OneEuroFilter {
    var minCutoff: Double
    var beta: Double
    var dCutoff: Double = 1.0
    private var xPrev: Double?
    private var dxPrev: Double = 0
    private var tPrev: Double?

    init(minCutoff: Double = 1.0, beta: Double = 0.02) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    private func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    mutating func filter(_ x: Double, at t: Double) -> Double {
        guard let xp = xPrev, let tp = tPrev, t > tp else {
            xPrev = x; tPrev = t; return x
        }
        let dt = t - tp
        let dx = (x - xp) / dt
        let aD = alpha(dCutoff, dt)
        let dxHat = aD * dx + (1 - aD) * dxPrev
        let cutoff = minCutoff + beta * abs(dxHat)
        let a = alpha(cutoff, dt)
        let xHat = a * x + (1 - a) * xp
        xPrev = xHat; dxPrev = dxHat; tPrev = t
        return xHat
    }

    mutating func reset() { xPrev = nil; dxPrev = 0; tPrev = nil }
}
