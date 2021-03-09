import Foundation
@_implementationOnly import GRPC

public class CoreClass {
    public init() {
        let statusCode = GRPCStatus.Code.alreadyExists
        print(statusCode)
    }
}
