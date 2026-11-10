import Testing
@testable import WhoIsThereCore

@Test func versionIsSet() {
    #expect(WhoIsThereVersion.current == "0.1.0")
}
