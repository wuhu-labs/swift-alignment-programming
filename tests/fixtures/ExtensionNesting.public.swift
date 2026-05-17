// ExtensionNesting public API outline

public struct Outer {
  public struct Tool: Runnable {
    public struct Input {
      public init()
    }

    public struct Result {
      public init()
    }

    public init()
    public func execute(input: Input) -> Result
  }

  public init()
}

public protocol Runnable {
}

extension Outer {
  public func tool() -> Tool
}
