BEGIN {
    print "const unsigned int fixture_data[] = {"
    state = 17
    for (i = 0; i < 900000; i++) {
        state = (state * 16807) % 2147483647
        printf "%.0fu,\n", state
    }
    print "};"
    print "unsigned int fixture_value(unsigned int i) { return fixture_data[i % 900000]; }"
}
