import SwiftAST
import SwiftRewriterLib

public class BaseGlobalsProvider: GlobalsProvider {
    var globals: [CodeDefinition] = []
    var types: [KnownType] = []
    var typealiases: [String: SwiftType] = [:]
    
    init() {
        createDefinitions()
        createTypes()
        createTypealiases()
    }
    
    public func registerDefinitions(on globals: GlobalDefinitions) {
        for global in self.globals {
            globals.recordDefinition(global)
        }
    }
    
    public func registerTypes(in typeSink: KnownTypeSink) {
        for type in types {
            typeSink.addType(type)
        }
    }
    
    public func registerTypealiases(in typealiasSink: TypealiasSink) {
        for (source, target) in typealiases {
            typealiasSink.addTypealias(aliasName: source, originalType: target)
        }
    }
    
    func createDefinitions() {
        
    }
    
    func createTypes() {
        
    }
    
    func createTypealiases() {
        
    }
    
    func addTypealias(from source: String, to target: SwiftType) {
        typealiases[source] = target
    }
    
    func add(_ definition: CodeDefinition) {
        globals.append(definition)
    }
    
    func add(_ type: KnownType) {
        types.append(type)
    }
    
    func makeType(named name: String, supertype: KnownTypeReferenceConvertible? = nil,
                  kind: KnownTypeKind = .class,
                  initializer: (KnownTypeBuilder) -> (KnownType) = { $0.build() }) {
        
        let builder = KnownTypeBuilder(typeName: name, supertype: supertype, kind: kind)
        
        let type = initializer(builder)
        
        add(type)
    }
    
    func constant(name: String, type: SwiftType) -> CodeDefinition {
        let storage = ValueStorage(type: type, ownership: .strong, isConstant: true)
        return CodeDefinition(variableNamed: name, storage: storage, intention: nil)
    }
    
    func variable(name: String, type: SwiftType) -> CodeDefinition {
        return CodeDefinition(variableNamed: name, type: type, intention: nil)
    }
    
    func function(name: String, paramsSignature: String, returnType: SwiftType = .void) -> CodeDefinition {
        let params = try! FunctionSignatureParser.parseParameters(from: paramsSignature)
        
        let signature =
            FunctionSignature(name: name, parameters: params,
                              returnType: returnType, isStatic: false)
        
        let definition = CodeDefinition(functionSignature: signature, intention: nil)
        
        return definition
    }
    
    func function(name: String, paramTypes: [SwiftType], returnType: SwiftType = .void) -> CodeDefinition {
        let paramSignatures = paramTypes.enumerated().map { (arg) -> ParameterSignature in
            let (i, type) = arg
            return ParameterSignature(label: "_", name: "p\(i)", type: type)
        }
        
        let signature =
            FunctionSignature(name: name, parameters: paramSignatures,
                              returnType: returnType, isStatic: false)
        
        let definition = CodeDefinition(functionSignature: signature, intention: nil)
        
        return definition
    }
}
