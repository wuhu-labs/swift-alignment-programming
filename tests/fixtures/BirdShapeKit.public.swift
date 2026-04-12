// BirdShapeKit public API outline

public typealias BirdID = UUID

public let defaultBirdName: String
public func describeBoundary(of shape: BirdShape) -> String
public func makeBirdShape(name: String = defaultBirdName, kind: BirdProfile.Kind = .swift) -> BirdShape
@MainActor public var publishedWingSpanLimit: Double

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public enum BirdAccent: String, Sendable, CaseIterable {
  case forest
  case sky
  case sunset
}

public enum BirdPalette {
  public static let sunrise: [String]
}

public struct BirdProfile: Sendable, Hashable, Codable {
  public enum Kind: String, Sendable, Codable, CaseIterable {
    case albatross
    case sparrow
    case swift
  }

  public struct Metrics: Sendable, Hashable, Codable {
    public var massGrams: Double
    public var wingspanCentimeters: Double
    public init(wingspanCentimeters: Double, massGrams: Double)
  }

  public var kind: Kind
  public var metrics: Metrics
  public var name: String
  public var shortLabel: String { get }
  public static let sample: BirdProfile
  public init(name: String = defaultBirdName, kind: Kind, metrics: Metrics)
}

public protocol BirdRenderable {
  var outlineDescription: String { get }
}

public struct BirdShape: BirdRenderable, Sendable, Hashable, Codable {
  public struct ControlPoint: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double)
  }

  public enum WingStyle: String, Sendable, Codable, CaseIterable {
    case pointed
    case rounded

    public static var recommendedForDistance: WingStyle { get }
  }

  public var outlineDescription: String { get }
  public var points: [ControlPoint]
  public var profile: BirdProfile
  public var wingStyle: WingStyle
  public init(profile: BirdProfile, wingStyle: WingStyle, points: [ControlPoint])
  public func scaled(by factor: Double) -> BirdShape
}

extension Array where Element == BirdShape.ControlPoint {
  public var centroidDescription: String { get }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension EnvironmentValues {
  public var birdAccent: BirdAccent { get set }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension View {
  @MainActor public func birdAccent(_ accent: BirdAccent) -> some View
}
