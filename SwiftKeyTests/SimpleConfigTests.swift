import Testing
import Foundation

@Suite("Simple Tests")
struct SimpleConfigTests {
    
    @Test("Basic math works")
    func basicMath() {
        #expect(2 + 2 == 4)
    }
    
    @Test("String operations work")
    func stringOperations() {
        let str = "Hello, World!"
        #expect(str.count == 13)
        #expect(str.hasPrefix("Hello"))
    }
    
    @Test("Array operations work")
    func arrayOperations() {
        var array = [1, 2, 3]
        array.append(4)
        #expect(array.count == 4)
        #expect(array.last == 4)
    }
}