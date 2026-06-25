import Foundation

/// A pure QR module grid: the symbol's data region with NO quiet zone. `true`
/// means a dark module. Rendering, quiet-zone padding and file output are all
/// kept separate from this value type (spec §7.2).
public struct QRCodeMatrix: Equatable {

    /// Number of modules per side of the data region (21, 25, … 177 for v1–v40).
    public let moduleCount: Int
    /// `modules[row][col]`, indexed from the top-left, `true` == dark.
    public let modules: [[Bool]]

    public init(moduleCount: Int, modules: [[Bool]]) {
        self.moduleCount = moduleCount
        self.modules = modules
    }

    /// QR version derived from the module count (size = 4·version + 17).
    public var version: Int { (moduleCount - 17) / 4 }

    /// Whether the grid is a valid square whose size maps to a real QR version.
    public var isWellFormed: Bool {
        guard moduleCount >= 21, (moduleCount - 17) % 4 == 0 else { return false }
        guard modules.count == moduleCount else { return false }
        return modules.allSatisfy { $0.count == moduleCount }
    }

    public func isDark(row: Int, col: Int) -> Bool {
        guard row >= 0, row < moduleCount, col >= 0, col < moduleCount else { return false }
        return modules[row][col]
    }

    /// A new grid surrounded by `quietZoneModules` of light modules on every
    /// side (spec §7.3 — default 4). The result's `moduleCount` includes the
    /// quiet zone, so it is no longer a bare data region; use it only for
    /// layout math, not as another `QRCodeMatrix` symbol.
    public func paddedGrid(quietZoneModules: Int) -> PaddedQRGrid {
        let q = max(0, quietZoneModules)
        let total = moduleCount + 2 * q
        var grid = [[Bool]](repeating: [Bool](repeating: false, count: total), count: total)
        for r in 0..<moduleCount {
            for c in 0..<moduleCount where modules[r][c] {
                grid[r + q][c + q] = true
            }
        }
        return PaddedQRGrid(totalModuleCount: total, quietZoneModules: q, dataModuleCount: moduleCount, modules: grid)
    }

    /// Count of dark modules (used in scanability heuristics / tests).
    public var darkModuleCount: Int {
        modules.reduce(0) { $0 + $1.filter { $0 }.count }
    }
}

/// A QR grid with quiet zone already baked in, ready for raster/vector drawing.
public struct PaddedQRGrid {
    public let totalModuleCount: Int
    public let quietZoneModules: Int
    public let dataModuleCount: Int
    public let modules: [[Bool]]

    public func isDark(row: Int, col: Int) -> Bool {
        guard row >= 0, row < totalModuleCount, col >= 0, col < totalModuleCount else { return false }
        return modules[row][col]
    }

    /// Maximal horizontal runs of dark modules per row, as (startCol, length).
    /// Drawing one rectangle per run keeps PDF/EPS output compact (spec §7.2).
    public func darkRuns(inRow row: Int) -> [(start: Int, length: Int)] {
        guard row >= 0, row < totalModuleCount else { return [] }
        var runs: [(Int, Int)] = []
        var col = 0
        let line = modules[row]
        while col < totalModuleCount {
            if line[col] {
                let start = col
                while col < totalModuleCount && line[col] { col += 1 }
                runs.append((start, col - start))
            } else {
                col += 1
            }
        }
        return runs
    }
}
