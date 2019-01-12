import SwiftAST

/// Specifies a definition for a global function or variable, or a local variable
/// of a function.
public class CodeDefinition {
    public var name: String {
        get {
            return kind.name
        }
        set {
            kind.name = newValue
        }
    }
    
    public var kind: Kind
    
    /// Gets the type signature for this definition.
    /// In case this is a function definition, the type represents the closure
    /// signature of the function.
    public var type: SwiftType {
        switch kind {
        case .variable(_, let storage):
            return storage.type
        case .function(let signature):
            return signature.swiftClosureType
        }
    }
    
    /// Attempts to return the value of this code definition as a function signature,
    /// if it can be implicitly interpreted as one.
    public var asFunctionSignature: FunctionSignature? {
        switch kind {
        case .function(let signature):
            return signature
            
        case .variable:
            return nil
        }
    }
    
    fileprivate convenience init(variableNamed name: String, type: SwiftType) {
        self.init(variableNamed: name,
                  storage: ValueStorage(type: type,
                                        ownership: .strong,
                                        isConstant: false))
    }
    
    fileprivate convenience init(constantNamed name: String, type: SwiftType) {
        self.init(variableNamed: name,
                  storage: ValueStorage(type: type,
                                        ownership: .strong,
                                        isConstant: true))
    }
    
    fileprivate init(variableNamed name: String, storage: ValueStorage) {
        kind = .variable(name: name, storage: storage)
    }
    
    fileprivate init(functionSignature: FunctionSignature) {
        kind = .function(signature: functionSignature)
    }
    
    public enum Kind: Hashable {
        case variable(name: String, storage: ValueStorage)
        case function(signature: FunctionSignature)
        
        public var name: String {
            get {
                switch self {
                case .variable(let name, _):
                    return name
                    
                case .function(let signature):
                    return signature.name
                }
            }
            set {
                switch self {
                case .variable(_, let storage):
                    self = .variable(name: newValue, storage: storage)
                    
                case .function(var signature):
                    signature.name = newValue
                    self = .function(signature: signature)
                }
            }
        }
    }
}

public extension CodeDefinition {
    /// Creates a set of code definitions that correspond to the parameters of a
    /// given function signature
    static func forParameters(inSignature signature: FunctionSignature) -> [CodeDefinition] {
        return forParameters(signature.parameters)
    }
    
    /// Creates a set of code definitions that correspond to the given set of
    /// parameters
    static func forParameters(_ parameters: [ParameterSignature]) -> [CodeDefinition] {
        return parameters.enumerated().map { (i, param) in
            LocalCodeDefinition(variableNamed: param.name,
                                type: param.type,
                                location: .parameter(index: i))
        }
    }
    
    /// Creates a set of code definitions that correspond to the given set of
    /// block parameters
    static func forParameters(_ parameters: [BlockParameter]) -> [CodeDefinition] {
        return parameters.enumerated().map { (i, param) in
            LocalCodeDefinition(variableNamed: param.name,
                                type: param.type,
                                location: .parameter(index: i))
        }
    }
    
    /// Creates a code definition that matches the instance or static type of
    /// `type`.
    /// Used for creating self intrinsics for member bodies.
    static func forSelf(type: SwiftType, isStatic: Bool) -> CodeDefinition {
        return LocalCodeDefinition(constantNamed: "self",
                                   type: isStatic ? .metatype(for: type) : type,
                                   location: isStatic ? .staticSelf : .instanceSelf)
    }
    
    /// Creates a code definition that matches the instance or static type of
    /// `super`.
    /// Used for creating self intrinsics for member bodies.
    static func forSuper(type: SwiftType, isStatic: Bool) -> CodeDefinition {
        return LocalCodeDefinition(constantNamed: "super",
                                   type: isStatic ? .metatype(for: type) : type,
                                   location: isStatic ? .staticSelf : .instanceSelf)
    }
    
    /// Creates a code definition for the setter of a setter method body.
    static func forSetterValue(named name: String, type: SwiftType) -> CodeDefinition {
        return LocalCodeDefinition(constantNamed: name,
                                   type: type,
                                   location: .setterValue)
    }
    
    /// Creates a code definition for a local identifier
    static func forLocalIdentifier(_ identifier: String,
                                   type: SwiftType,
                                   isConstant: Bool,
                                   location: LocalCodeDefinition.DefinitionLocation) -> CodeDefinition {
        
        if isConstant {
            return LocalCodeDefinition(constantNamed: identifier,
                                       type: type,
                                       location: location)
        }
        
        return LocalCodeDefinition(variableNamed: identifier,
                                   type: type,
                                   location: location)
    }
    
    static func forGlobalFunction(_ function: GlobalFunctionGenerationIntention) -> CodeDefinition {
        return GlobalIntentionCodeDefinition(intention: function)
    }
    
    static func forGlobalVariable(_ variable: GlobalVariableGenerationIntention) -> CodeDefinition {
        return GlobalIntentionCodeDefinition(intention: variable)
    }
    
    static func forGlobalFunction(signature: FunctionSignature) -> CodeDefinition {
        return GlobalCodeDefinition(functionSignature: signature)
    }
    
    static func forGlobalVariable(name: String, isConstant: Bool, type: SwiftType) -> CodeDefinition {
        if isConstant {
            return GlobalCodeDefinition(constantNamed: name, type: type)
        }
        
        return GlobalCodeDefinition(variableNamed: name, type: type)
    }
    
    static func forKnownMember(_ knownMember: KnownMember) -> CodeDefinition {
        return KnownMemberCodeDefinition(knownMember: knownMember)
    }
    
    static func forType(named name: String) -> TypeCodeDefinition {
        return TypeCodeDefinition(constantNamed: name,
                                  type: .metatype(for: .typeName(name)))
    }
}

/// A code definition derived from a `KnownMember` instance
public class KnownMemberCodeDefinition: CodeDefinition {
    
    fileprivate init(knownMember: KnownMember) {
        switch knownMember {
        case let prop as KnownProperty:
            super.init(variableNamed: prop.name,
                       storage: prop.storage)
            
        case let method as KnownMethod:
            super.init(functionSignature: method.signature)
            
        default:
            fatalError("Attempting to create a \(KnownMemberCodeDefinition.self) from unkown \(KnownMember.self)-type \(Swift.type(of: knownMember))")
        }
    }
}

/// A code definition that refers to a type of matching name
public class TypeCodeDefinition: CodeDefinition {
    
}
extension TypeCodeDefinition: Equatable {
    public static func == (lhs: TypeCodeDefinition, rhs: TypeCodeDefinition) -> Bool {
        return lhs.name == rhs.name
    }
}

public class GlobalCodeDefinition: CodeDefinition {
    fileprivate func isEqual(to other: GlobalCodeDefinition) -> Bool {
        return kind == other.kind
    }
}
extension GlobalCodeDefinition: Equatable {
    public static func == (lhs: GlobalCodeDefinition, rhs: GlobalCodeDefinition) -> Bool {
        return lhs.isEqual(to: rhs)
    }
}

public class GlobalIntentionCodeDefinition: GlobalCodeDefinition {
    public let intention: Intention
    
    fileprivate init(intention: Intention) {
        self.intention = intention
        
        switch intention {
        case let intention as GlobalVariableGenerationIntention:
            super.init(variableNamed: intention.name,
                       storage: intention.storage)
            
        case let intention as GlobalFunctionGenerationIntention:
            super.init(functionSignature: intention.signature)
            
        default:
            fatalError("Attempting to create global code definition for non-definition intention type \(Swift.type(of: intention))")
        }
    }
    
    fileprivate override func isEqual(to other: GlobalCodeDefinition) -> Bool {
        if let other = other as? GlobalIntentionCodeDefinition {
            return intention === other.intention
        }
        
        return super.isEqual(to: other)
    }
}

public class LocalCodeDefinition: CodeDefinition {
    var location: DefinitionLocation
    
    fileprivate convenience init(variableNamed name: String,
                                 type: SwiftType,
                                 location: DefinitionLocation) {
        
        self.init(variableNamed: name,
                  storage: ValueStorage(type: type,
                                        ownership: .strong,
                                        isConstant: false),
                  location: location)
    }
    
    fileprivate convenience init(constantNamed name: String,
                                 type: SwiftType,
                                 location: DefinitionLocation) {
        
        self.init(variableNamed: name,
                  storage: ValueStorage(type: type,
                                        ownership: .strong,
                                        isConstant: true),
                  location: location)
    }
    
    fileprivate init(variableNamed name: String, storage: ValueStorage, location: DefinitionLocation) {
        self.location = location
        
        super.init(variableNamed: name, storage: storage)
    }
    
    fileprivate init(functionSignature: FunctionSignature, location: DefinitionLocation) {
        self.location = location
        
        super.init(functionSignature: functionSignature)
    }
    
    public enum DefinitionLocation: Hashable {
        case instanceSelf
        case staticSelf
        case setterValue
        case parameter(index: Int)
        case variableDeclaration(VariableDeclarationsStatement, index: Int)
        case forLoop(ForStatement, PatternLocation)
        case ifLet(IfStatement, PatternLocation)
        
        public static func == (lhs: DefinitionLocation, rhs: DefinitionLocation) -> Bool {
            switch (lhs, rhs) {
            case (.instanceSelf, .instanceSelf),
                 (.staticSelf, .staticSelf),
                 (.setterValue, .setterValue):
                return true
                
            case let (.parameter(l), .parameter(r)):
                return l == r
                
            case let (.variableDeclaration(d1, i1), .variableDeclaration(d2, i2)):
                return d1 === d2 && i1 == i2
                
            case let (.forLoop(f1, loc1), .forLoop(f2, loc2)):
                return f1 === f2 && loc1 == loc2
                
            case let (.ifLet(if1, loc1), .ifLet(if2, loc2)):
                return if1 === if2 && loc1 == loc2
                
            default:
                return false
            }
        }
        
        public func hash(into hasher: inout Hasher) {
            switch self {
            case .instanceSelf:
                hasher.combine(1)
                
            case .staticSelf:
                hasher.combine(2)
                
            case .setterValue:
                hasher.combine(3)
                
            case .parameter(let index):
                hasher.combine(4)
                hasher.combine(index)
                
            case let .variableDeclaration(stmt, index):
                hasher.combine(ObjectIdentifier(stmt))
                hasher.combine(index)
                
            case let .forLoop(stmt, loc):
                hasher.combine(ObjectIdentifier(stmt))
                hasher.combine(loc)
                
            case let .ifLet(stmt, loc):
                hasher.combine(ObjectIdentifier(stmt))
                hasher.combine(loc)
            }
        }
    }
}

extension LocalCodeDefinition: Equatable {
    public static func == (lhs: LocalCodeDefinition, rhs: LocalCodeDefinition) -> Bool {
        return lhs === rhs || lhs.location == rhs.location
    }
}
extension LocalCodeDefinition: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(location)
    }
}
