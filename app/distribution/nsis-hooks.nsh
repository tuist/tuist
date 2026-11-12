; cargo-packager 0.11.7's uninstall template compares $R7 using compile-time
; !if, not a runtime LogicLib condition. Clean up our per-user protocol only
; after a successful uninstall and only if another application hasn't taken it.
Function un.onUninstSuccess
  ReadRegStr $R7 HKCU "Software\Classes\tuist\shell\open\command" ""
  ${If} $R7 == "$\"$INSTDIR\Tuist.exe$\" $\"%1$\""
    DeleteRegKey HKCU "Software\Classes\tuist"
  ${EndIf}
FunctionEnd
