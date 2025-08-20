Code.require_file("../../test/test_helper.exs", __DIR__)

# Add additional Mimic copies for runner tests
Mimic.copy(Runner.QA.AppiumClient)
