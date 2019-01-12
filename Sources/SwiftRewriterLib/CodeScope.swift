import SwiftAST

private let _codeScopeKey = "_codeScopeKey"
private let _identifierDefinitionKey = "_identifierDefinitionKey"

/// Protocol for statements that feature code scoping.
public protocol CodeScopeNode: CodeScope {
    var definitions: CodeScope { get }
}

public extension CodeScopeNode where Self: SyntaxNode {
    public var definitions: CodeScope {
        if let scope = metadata[_codeScopeKey] as? CodeScope {
            return scope
        }
        let scope = DefaultCodeScope()
        metadata[_codeScopeKey] = scope
        
        return scope
    }
    
    public func firstDefinition(named name: String) -> CodeDefinition? {
        if let def = definitions.firstDefinition(named: name) {
            return def
        }
        
        return nearestScopeThatIsNotSelf?.firstDefinition(named: name)
    }
    
    public func functionDefinitions(matching identifier: FunctionIdentifier) -> [CodeDefinition] {
        let defs =
            nearestScopeThatIsNotSelf?
                .functionDefinitions(matching: identifier)
                    ?? []
        
        return definitions.functionDefinitions(matching: identifier) + defs
    }
    
    public func allDefinitions() -> [CodeDefinition] {
        return definitions.allDefinitions()
    }
    
    public func recordDefinition(_ definition: CodeDefinition) {
        definitions.recordDefinition(definition)
    }
    
    public func recordDefinitions(_ definitions: [CodeDefinition]) {
        self.definitions.recordDefinitions(definitions)
    }
    
    public func removeAllDefinitions() {
        definitions.removeAllDefinitions()
    }
}

public extension SyntaxNode {
    /// Finds the nearest definition scope in the hierarchy chain for this syntax
    /// node.
    public var nearestScope: CodeScopeNode? {
        var parent: SyntaxNode? = self
        while let p = parent {
            if let scope = p as? CodeScopeNode {
                return scope
            }
            
            parent = p.parent
        }
        
        return nil
    }
    
    /// Finds the nearest definition scope in the hierarchy chain for this syntax
    /// node which is not `self`
    internal var nearestScopeThatIsNotSelf: CodeScopeNode? {
        var parent: SyntaxNode? = self
        while let p = parent {
            parent = p.parent
            
            if p !== self, let scope = p as? CodeScopeNode {
                return scope
            }
        }
        
        return nil
    }
}

extension CompoundStatement: CodeScopeNode { }
extension BlockLiteralExpression: CodeScopeNode { }

/// A no-op code scope to return when requesting code scope for statements that
/// are not contained within a valid compound statement.
class EmptyCodeScope: CodeScope {
    func firstDefinition(named name: String) -> CodeDefinition? {
        return nil
    }
    func functionDefinitions(matching identifier: FunctionIdentifier) -> [CodeDefinition] {
        return []
    }
    func allDefinitions() -> [CodeDefinition] {
        return []
    }
    func recordDefinition(_ definition: CodeDefinition) { }
    func recordDefinitions(_ definitions: [CodeDefinition]) { }
    func removeAllDefinitions() { }
}

/// An object that can provide definitions for a type resolver
public protocol DefinitionsSource {
    func firstDefinition(named name: String) -> CodeDefinition?
    
    /// Returns all function definitions that match a given function identifier
    func functionDefinitions(matching identifier: FunctionIdentifier) -> [CodeDefinition]
    
    /// Returns all definitions from this local scope only
    func allDefinitions() -> [CodeDefinition]
}

/// A code scope that stores definitions gathered during function body analysis.
/// Is used only during statement rewriting phase.
public protocol CodeScope: DefinitionsSource {
    func recordDefinition(_ definition: CodeDefinition)
    func recordDefinitions(_ definitions: [CodeDefinition])
    func removeAllDefinitions()
}

public struct ArrayDefinitionsSource: DefinitionsSource {
    private var definitionsByName: [String: CodeDefinition] = [:]
    private var functionDefinitions: [FunctionIdentifier: [CodeDefinition]] = [:]
    private var definitions: [CodeDefinition]
    
    public init(definitions: [CodeDefinition] = []) {
        self.definitions = definitions
        self.definitionsByName = definitions
            .groupBy { $0.name }
            .mapValues { $0[0] }
        
        self.functionDefinitions =
            definitions
                .compactMap { def -> (FunctionIdentifier, CodeDefinition)? in
                    switch def.kind {
                    case .function(let signature):
                        return (signature.asIdentifier, def)
                    case .variable:
                        return nil
                    }
                }.groupBy({ $0.0 })
                .mapValues { $0.map { $0.1 } }
    }
    
    public func firstDefinition(named name: String) -> CodeDefinition? {
        return definitionsByName[name]
    }
    
    public func functionDefinitions(matching identifier: FunctionIdentifier) -> [CodeDefinition] {
        return functionDefinitions[identifier] ?? []
    }
    
    public func allDefinitions() -> [CodeDefinition] {
        return definitions
    }
}

/// A definitions source composed of individual definition sources composed as
/// a single definition source.
public class CompoundDefinitionsSource: DefinitionsSource {
    private var sources: [DefinitionsSource]
    
    public init() {
        sources = []
    }
    
    public init(sources: [DefinitionsSource]) {
        self.sources = sources
    }
    
    public func addSource(_ definitionSource: DefinitionsSource) {
        sources.append(definitionSource)
    }
    
    public func firstDefinition(named name: String) -> CodeDefinition? {
        for source in sources {
            if let def = source.firstDefinition(named: name) {
                return def
            }
        }
        
        return nil
    }
    
    public func functionDefinitions(matching identifier: FunctionIdentifier) -> [CodeDefinition] {
        var definitions: [CodeDefinition] = []
        
        for source in sources {
            let defs = source.functionDefinitions(matching: identifier)
            
            definitions.append(contentsOf: defs)
        }
        
        return definitions
    }
    
    public func allDefinitions() -> [CodeDefinition] {
        return sources.flatMap { $0.allDefinitions() }
    }
}

/// A default implementation of a code scope
public final class DefaultCodeScope: CodeScope {
    private var definitionsByName: [String: CodeDefinition] = [:]
    private var functionDefinitions: [FunctionIdentifier: [CodeDefinition]] = [:]
    internal var definitions: [CodeDefinition]
    
    public init(definitions: [CodeDefinition] = []) {
        self.definitions = definitions
        self.definitionsByName = definitions
            .groupBy { $0.name }
            .mapValues { $0[0] }
        
        self.functionDefinitions =
            definitions
                .compactMap { def -> (FunctionIdentifier, CodeDefinition)? in
                    switch def.kind {
                    case .function(let signature):
                        return (signature.asIdentifier, def)
                    case .variable:
                        return nil
                    }
                }.groupBy({ $0.0 })
                .mapValues { $0.map { $0.1 } }
    }
    
    public func firstDefinition(named name: String) -> CodeDefinition? {
        return definitionsByName[name]
    }
    
    public func functionDefinitions(matching identifier: FunctionIdentifier) -> [CodeDefinition] {
        return functionDefinitions[identifier] ?? []
    }
    
    public func allDefinitions() -> [CodeDefinition] {
        return definitions
    }
    
    public func recordDefinition(_ definition: CodeDefinition) {
        definitions.append(definition)
        definitionsByName[definition.name] = definition
        
        switch definition.kind {
        case .function(let signature):
            functionDefinitions[signature.asIdentifier, default: []].append(definition)
            
        case .variable:
            break
        }
    }
    
    public func recordDefinitions(_ definitions: [CodeDefinition]) {
        for def in definitions {
            recordDefinition(def)
        }
    }
    
    public func removeAllDefinitions() {
        definitions.removeAll()
        definitionsByName.removeAll()
    }
}

public extension IdentifierExpression {
    /// Gets the definition this identifier references.
    /// To gather definitions to identifiers, use a `ExpressionTypeResolver` on
    /// the syntax tree this identifier is contained in.
    public var definition: CodeDefinition? {
        get {
            return metadata[_identifierDefinitionKey] as? CodeDefinition
        }
        set {
            metadata[_identifierDefinitionKey] = newValue
        }
    }
    
    public func settingDefinition(_ definition: CodeDefinition) -> IdentifierExpression {
        let new = copy()
        new.definition = definition
        return new
    }
}

public extension MemberPostfix {
    /// Gets the member this member postfix operation references
    public var memberDefinition: KnownMember? {
        get {
            return metadata[_identifierDefinitionKey] as? KnownMember
        }
        set {
            metadata[_identifierDefinitionKey] = newValue
        }
    }
}
