import Foundation
import Mocker

public enum NetworkResponseMocks {
    public static var testMock: Mock {
        Mock(
            url: URL(string: "https://apple.com")!,
            dataType: .json,
            statusCode: 200,
            data: [.get: Data()]
        )
    }
}
