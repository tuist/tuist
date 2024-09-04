import UIKit

var a = Set(arrayLiteral: "A", "B")
var b = Set(["A", "B"])

!b.isEmpty
b = b.intersection(a)
!b.isEmpty
