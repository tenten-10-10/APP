import Foundation

// MARK: - Domain enumerations
//
// Core Data stores these as raw `String` attributes (the `…Raw` properties on
// the managed objects) so the schema stays CloudKit-friendly and forward
// compatible: an unknown future raw value decodes to a safe `.unknown`-style
// fallback instead of crashing. Each enum therefore provides a non-failable
// initializer from an optional raw string.

/// How a `Product` tracks its stock.
public enum TrackingMode: String, CaseIterable, Identifiable {
    /// A single fungible quantity (e.g. screws, cable, paint).
    case quantity
    /// Individually tracked units, each with its own serial / status.
    case individual
    /// Tracked by lot / batch: each lot carries its own quantity, QR label and
    /// optional expiry date.
    case lot

    public var id: String { rawValue }

    public init(raw: String?) {
        self = TrackingMode(rawValue: raw ?? "") ?? .quantity
    }

    public var localizedTitle: String {
        switch self {
        case .quantity:   return NSLocalizedString("数量管理", comment: "tracking mode")
        case .individual: return NSLocalizedString("個体管理", comment: "tracking mode")
        case .lot:        return NSLocalizedString("ロット管理", comment: "tracking mode")
        }
    }

    public var explanation: String {
        switch self {
        case .quantity:   return NSLocalizedString("まとめて数量で管理します。", comment: "")
        case .individual: return NSLocalizedString("1点ずつシリアル番号で管理します。", comment: "")
        case .lot:        return NSLocalizedString("ロット（製造単位）ごとに数量と期限を管理します。", comment: "")
        }
    }
}

/// Whether a `StockUnit` represents a single serialised item or a lot/batch
/// carrying a quantity.
public enum UnitKind: String, CaseIterable, Identifiable {
    case serial
    case lot

    public var id: String { rawValue }

    public init(raw: String?) {
        self = UnitKind(rawValue: raw ?? "") ?? .serial
    }

    public var localizedTitle: String {
        switch self {
        case .serial: return NSLocalizedString("シリアル", comment: "unit kind")
        case .lot:    return NSLocalizedString("ロット", comment: "unit kind")
        }
    }
}

/// Lifecycle status of an individually tracked `StockUnit`.
public enum UnitStatus: String, CaseIterable, Identifiable {
    case available
    case checkedOut
    case consumed
    case retired

    public var id: String { rawValue }

    public init(raw: String?) {
        self = UnitStatus(rawValue: raw ?? "") ?? .available
    }

    public var localizedTitle: String {
        switch self {
        case .available:  return NSLocalizedString("利用可能", comment: "unit status")
        case .checkedOut: return NSLocalizedString("貸出中", comment: "unit status")
        case .consumed:   return NSLocalizedString("消費済み", comment: "unit status")
        case .retired:    return NSLocalizedString("廃棄", comment: "unit status")
        }
    }

    /// `true` if the unit still contributes to on-hand stock.
    public var isOnHand: Bool { self == .available }
}

/// Physical kind of a `Location` node in the storage hierarchy.
public enum LocationKind: String, CaseIterable, Identifiable {
    case site
    case room
    case shelf
    case bin
    case container
    case other

    public var id: String { rawValue }

    public init(raw: String?) {
        self = LocationKind(rawValue: raw ?? "") ?? .other
    }

    public var localizedTitle: String {
        switch self {
        case .site:      return NSLocalizedString("拠点", comment: "location kind")
        case .room:      return NSLocalizedString("部屋", comment: "location kind")
        case .shelf:     return NSLocalizedString("棚", comment: "location kind")
        case .bin:       return NSLocalizedString("ビン", comment: "location kind")
        case .container: return NSLocalizedString("コンテナ", comment: "location kind")
        case .other:     return NSLocalizedString("その他", comment: "location kind")
        }
    }

    public var systemImageName: String {
        switch self {
        case .site:      return "building.2"
        case .room:      return "door.left.hand.open"
        case .shelf:     return "books.vertical"
        case .bin:       return "tray"
        case .container: return "shippingbox"
        case .other:     return "mappin.and.ellipse"
        }
    }

    /// Kinds that can sensibly hold products/units and be bulk-moved.
    public var isContainerLike: Bool {
        switch self {
        case .bin, .container, .shelf: return true
        case .site, .room, .other:     return false
        }
    }
}

/// The kind of change an `InventoryEvent` records. The ledger is the source of
/// truth; quantity caches are derived from these deltas.
public enum InventoryEventType: String, CaseIterable, Identifiable {
    case create
    case receive
    case consume
    case adjust
    case transfer
    case checkout
    case returned = "return"   // raw value kept as "return" for data compatibility
    case retire
    case correction

    public var id: String { rawValue }

    public init(raw: String?) {
        self = InventoryEventType(rawValue: raw ?? "") ?? .adjust
    }

    public var localizedTitle: String {
        switch self {
        case .create:     return NSLocalizedString("初期登録", comment: "event type")
        case .receive:    return NSLocalizedString("入庫", comment: "event type")
        case .consume:    return NSLocalizedString("消費・出庫", comment: "event type")
        case .adjust:     return NSLocalizedString("棚卸し調整", comment: "event type")
        case .transfer:   return NSLocalizedString("場所移動", comment: "event type")
        case .checkout:   return NSLocalizedString("貸出", comment: "event type")
        case .returned:   return NSLocalizedString("返却", comment: "event type")
        case .retire:     return NSLocalizedString("廃棄・無効化", comment: "event type")
        case .correction: return NSLocalizedString("訂正", comment: "event type")
        }
    }

    public var systemImageName: String {
        switch self {
        case .create:     return "plus.circle"
        case .receive:    return "arrow.down.circle"
        case .consume:    return "minus.circle"
        case .adjust:     return "slider.horizontal.3"
        case .transfer:   return "arrow.left.arrow.right.circle"
        case .checkout:   return "person.crop.circle.badge.arrow.up"
        case .returned:   return "arrow.uturn.left.circle"
        case .retire:     return "trash.circle"
        case .correction: return "pencil.circle"
        }
    }

    /// Whether this event type carries a meaningful quantity delta that feeds
    /// the on-hand running total for quantity-tracked products.
    public var affectsQuantityTotal: Bool {
        switch self {
        case .create, .receive, .consume, .adjust, .returned, .checkout, .correction:
            return true
        case .transfer, .retire:
            // Transfers move location but don't change total on-hand count.
            // Retire is handled per-unit, not via the quantity total.
            return false
        }
    }
}

/// What a `CodeAlias` (QR label) currently points at.
public enum CodeTargetType: String, CaseIterable, Identifiable {
    case unassigned
    case product
    case unit
    case location

    public var id: String { rawValue }

    public init(raw: String?) {
        self = CodeTargetType(rawValue: raw ?? "") ?? .unassigned
    }

    public var localizedTitle: String {
        switch self {
        case .unassigned: return NSLocalizedString("未割当", comment: "code target")
        case .product:    return NSLocalizedString("製品", comment: "code target")
        case .unit:       return NSLocalizedString("個体", comment: "code target")
        case .location:   return NSLocalizedString("保管場所", comment: "code target")
        }
    }
}

/// Named accent colors for projects (stored as `colorKey`). Kept as a small
/// fixed palette so it round-trips through CloudKit as a short string.
public enum ProjectColor: String, CaseIterable, Identifiable {
    case blue, green, orange, red, purple, teal, pink, gray

    public var id: String { rawValue }

    public init(raw: String?) {
        self = ProjectColor(rawValue: raw ?? "") ?? .blue
    }
}
