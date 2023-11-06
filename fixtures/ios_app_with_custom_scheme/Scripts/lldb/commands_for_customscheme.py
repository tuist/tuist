try:
    import lldb
except:
    pass

def __lldb_init_module(debugger, internal_dict):
    print("commands_for_customscheme.py registered")
