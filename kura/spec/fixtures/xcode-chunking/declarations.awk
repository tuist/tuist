# Long, varied public names keep the compressed module above the chunk threshold.
# This is a transfer fixture, not a representative application or timing workload.
function name(prefix) {
    return sprintf("%s%08x%08x%08x", prefix, rand() * 2147483647, rand() * 2147483647, rand() * 2147483647)
}
BEGIN {
    srand(20260907)
    for (type = 0; type < 4000; type++) {
        print "public struct " name("Type_") " {"
        for (property = 0; property < 6; property++) {
            # Rename one stored property halfway through the module.
            prefix = rename_property && type == 2000 && property == 0 ? "edited_" : "p_"
            print "    public var " name(prefix) ": Int"
        }
        print "}"
    }
}
