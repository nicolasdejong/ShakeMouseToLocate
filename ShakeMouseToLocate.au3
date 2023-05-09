#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Compression=5   ;default 3
#AutoIt3Wrapper_UseUpx=n
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****

; ShakeMouseToLocate -- by Nicolas de Jong
; Original by Spinal Cord (http://spinalcode.co.uk/2018/11/06/windows-shake-to-find-cursor/)
;
; 2019-04-11 V1.0
; - Changed shake-detection because big mouse was showing too often
; - Added persistent flag: start with Windows
; - Added persistent flag: enabled (currently enables at startup anyway)
; - Added persistent flag: also press the control key
; - Altered application name to 'ShakeMouseToLocate' to stay close to
;   the Mac option it emulates
; - Altered tray tooltip to have almost the same text as the Mac equivalent
; - Altered 'About'
;

#include <TrayConstants.au3> ; Required for the $TRAY_ICONSTATE_SHOW constant.
#include <WindowsConstants.au3>
#Include <WinAPI.au3>
#include <GDIPlus.au3>
#include <Misc.au3>

#Region Globals

global const $SHAKE_DIST = 20
global const $SHAKE_SLICE_TIMEOUT = 50 ; milliseconds
global const $SHAKE_TIMEOUT = 400 ; milliseconds
global const $SHOWING_TIMEOUT = 600 ; milliseconds
global       $needed_shake_count = 3 ; set from configuration

global const $VERSION  = "1.0"
global const $APP_NAME = "ShakeMouseToLocate"
global const $EXE_NAME = @AutoItExe
global const $TRAY_TOOLTIP = $APP_NAME & " V" & $VERSION & " -- Quickly move the mouse pointer left and right to make it temporarily bigger";
global const $ABOUT_TEXT = $APP_NAME & " V" & $VERSION & @CRLF _
                          & @CRLF _
                          & "Shake or circle the mouse quickly and a big mouse" & @CRLF _
                          & "will show for a short while. This will help you find" & @CRLF _
                          & "back the mouse cursor." & @CRLF _
                          & @CRLF _
                          & "Forked by Nicolas de Jong (nicolas@rutilo.nl)" & @CRLF _
                          & "Original by Spinal Cord (http://spinalcode.co.uk/)" & @CRLF _
                          & @CRLF _
                          & "Altered because the original showed the big mouse" & @CRLF _
                          & "too often. Now it shows only after moving the mouse" & @CRLF _
                          & "pointer left and right quickly a few times." & @CRLF _
                          & @CRLF _
                          & "Also added flags for autostart, enabled, ctrl and" & @CRLF _
                          & "sensitivity."

global const $REGKEY_AUTORUN = "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
global const $REGKEY_CONFIG  = "HKCU\Software\" & $APP_NAME
global const $REGKEY_ENABLED = "Enabled"
global const $REGKEY_TCTRL   = "CtrlNeeded"
global const $REGKEY_SENSIT  = "Sensitivity"

global const $SENSITIVITY_HIGH   = 2
global const $SENSITIVITY_MEDIUM = 4
global const $SENSITIVITY_LOW    = 7

global Const $AC_SRC_ALPHA = 1

global $idAbout, $idExit, $idAutoStart, $idEnabled, $idUseCtrl, $idSensit, $idSensit0, $idSensit1, $idSensit2
global $hBmp, $hIcon
global $oldMX, $oldMY, $curMx, $curMY, $distX, $distY, $distPix
global $showing = 0
global $running = 1

#EndRegion ### Globals ###

#Region Init
;HotKeySet("{END}", "_Quit") ; Hit "END" to quit (during dev only)

$avMousePos = MouseGetPos()
$win_mouse = GUICreate($APP_NAME, 64, 64, $avMousePos[0], $avMousePos[1], $WS_POPUP, BitOR($WS_EX_LAYERED, $WS_EX_TOOLWINDOW))
WinSetOnTop($win_mouse, '', 1)

_GDIPlus_Startup()
$g_hImage = _GDIPlus_BitmapCreateFromMemory(_Torus())

GUISetState(@SW_SHOW)

_setEnabled()  ; 'enabled' is persistent so this statement can be removed if required
_createTray()

; timer for mouse tracking
$showingTimer = TimerInit()
$shakeSliceTimer = TimerInit()
$shakeTimeoutTimer = TimerInit()
$shakeCount = 0

global $nowX = 0, $oldX = 0, $minX = 0, $maxX = 0, $hasMin = 0, $hasMax = 0

#EndRegion Init

_getSensitivity()

While $running = 1
  $avMousePos = MouseGetPos()

  _detectMouseMoves()
  _updateMouse()
  _handleTrayEvents()
WEnd

Func _detectMouseMoves()
  $nowX = $avMousePos[0]
  if $nowX < $oldX Then
    If $hasMin = 0 Then
      $hasMin = 1
      $minX = $nowX
    Else
      $minX = _min($minX, $nowX)
    EndIf
  ElseIf $nowX > $oldX Then
    If $hasMax = 0 Then
    $hasMax = 1
    $maxX = $nowX
    Else
    $maxX = _max($maxX, $nowX)
    EndIf
  EndIf
  $oldX = $nowX
EndFunc
Func _isShaking()
  If _needsCtrl() And Not _isCtrlPressed() Then
    Return 0
  EndIf
  $isShaking = 0;
  If TimerDiff($shakeSliceTimer) >= $SHAKE_SLICE_TIMEOUT Then
    $shakeSliceTimer = TimerInit()

    If $hasMin = 1 And $hasMax = 1 And $maxX - $minX > $SHAKE_DIST Then
		  $shakeCount += 1
      $shakeTimeoutTimer = TimerInit()
	  EndIf

	  If $shakeCount >= $needed_shake_count AND _isEnabled() Then
      $showingTimer = TimerInit()
      $shakeCount= 0;
      $isShaking = 1;_showBig()
    EndIf

    $hasMin = 0
    $hasMax = 0
    $minX = 0
    $maxX = 0
  EndIf
  Return $isShaking
EndFunc
Func _moveBigMouse()
  WinMove($win_mouse, "", $avMousePos[0], $avMousePos[1])
  WinSetOnTop($win_mouse, '', 1)
EndFunc
Func _hideBigMouseOnTimeout()
  If TimerDiff($showingTimer) >= $SHOWING_TIMEOUT Then
    _hideBig()
    $shakeCount = 0
  EndIf
EndFunc
Func _updateMouse()
  If $showing = 1 Then
    _moveBigMouse()
    _hideBigMouseOnTimeout()
  Else
	  If _isShaking() Then
		 _showBig()
     _moveBigMouse()
	  EndIf
  EndIf

  If TimerDiff($shakeTimeoutTimer) >= $SHAKE_TIMEOUT Then
    $shakeCount = 0
  EndIf
EndFunc


Func _createTray ()

  Opt("TrayMenuMode", 3) ; The default tray menu items will not be shown and items are not checked when selected. These are options 1 and 2 for TrayMenuMode.

  $idAbout = TrayCreateItem("About")
  _TrayAddLine()
  $idAutoStart = TrayCreateItem("Start with Windows")
  $idEnabled = TrayCreateItem("Enabled")
  $idUseCtrl = TrayCreateItem("Also press ctrl to trigger")
  _TrayAddLine()
  $idSensit0 = TrayCreateItem("Sensitivity high")
  $idSensit1 = TrayCreateItem("Sensitivity medium")
  $idSensit2 = TrayCreateItem("Sensitivity low")
  _TrayAddLine()
  $idExit = TrayCreateItem("Exit")

  If RegRead($REGKEY_AUTORUN, $APP_NAME) <> '' Then
    TrayItemSetState($idAutoStart, $TRAY_CHECKED)
  EndIf

  If _isEnabled() Then
    TrayItemSetState($idEnabled, $TRAY_CHECKED)
  EndIf

  If _needsCtrl() Then
    TrayItemSetState($idUseCtrl, $TRAY_CHECKED)
  EndIf

  _setSensitivity(0) ; Initialize

  TraySetState($TRAY_ICONSTATE_SHOW) ; Show the tray menu.
  TraySetToolTip($TRAY_TOOLTIP)

  $hBmp = _GDIPlus_BitmapCreateFromMemory(_AutoIt_Icon()) ;load ico and convert it to a GDI+ bitmap
  ;convert bitmap to HIcon
  $hIcon = _GDIPlus_HICONCreateFromBitmap($hBmp)
  _WinAPI_TraySetHIcon($hIcon)

EndFunc
Func _TrayAddLine()
  TrayCreateItem("")
EndFunc
Func _handleTrayEvents()
  Switch TrayGetMsg()
    Case $idAbout
      MsgBox($MB_SYSTEMMODAL + $MB_ICONINFORMATION, $APP_NAME, $ABOUT_TEXT)

    Case $idAutoStart
      If RegRead($REGKEY_AUTORUN, $APP_NAME) = '' Then
        RegWrite($REGKEY_AUTORUN, $APP_NAME, "REG_SZ", '"' & $EXE_NAME & '"')
        TrayItemSetState($idAutoStart, $TRAY_CHECKED)
      Else
        RegDelete($REGKEY_AUTORUN, $APP_NAME)
        TrayItemSetState($idAutoStart, $TRAY_UNCHECKED)
      EndIf

    Case $idEnabled
      If _isEnabled() Then
        _setDisabled()
        TrayItemSetState($idEnabled, $TRAY_UNCHECKED)
      Else
        _setEnabled()
        TrayItemSetState($idEnabled, $TRAY_CHECKED)
      EndIf

    Case $idUseCtrl
      If _needsCtrl() Then
        _unsetCtrl()
        TrayItemSetState($idUseCtrl, $TRAY_UNCHECKED)
      Else
        _setCtrl()
        TrayItemSetState($idUseCtrl, $TRAY_CHECKED)
      EndIf

    Case $idSensit0
      _setSensitivity($SENSITIVITY_HIGH)

    Case $idSensit1
      _setSensitivity($SENSITIVITY_MEDIUM)

    Case $idSensit2
      _setSensitivity($SENSITIVITY_LOW)

    Case $idExit
      _Quit()
      $running = 0;

  EndSwitch
EndFunc

Func _showBig()
   If $showing = 0 Then
	  $showing = 1
      SetBitmap($win_mouse, $g_hImage, 200)
      WinSetOnTop($win_mouse, '', 1)
   EndIf
EndFunc
Func _hideBig()
   If $showing <> 0 Then
	  $showing = 0
      SetBitmap($win_mouse, $g_hImage, 0)
   EndIf
EndFunc

Func _min($a, $b)
   If $a < $b Then
	  Return $a
   Else
	  Return $b
   EndIf
EndFunc
Func _max($a, $b)
   If $a > $b Then
	  Return $a
   Else
	  Return $b
   EndIf
EndFunc

Func _log($msg)
   If @Compiled Then
	  DllCall("kernel32.dll", "none", "OutputDebugString", "str", $msg)
   Else
	  ConsoleWrite($msg & @CRLF)
   EndIf
EndFunc

Func _isEnabled()
   Return RegRead($REGKEY_CONFIG, $REGKEY_ENABLED) = "1"
EndFunc
Func _setEnabled()
   RegWrite($REGKEY_CONFIG, $REGKEY_ENABLED, "REG_SZ", "1");
EndFunc
Func _setDisabled()
   RegWrite($REGKEY_CONFIG, $REGKEY_ENABLED, "REG_SZ", "0");
EndFunc

Func _needsCtrl()
   Return RegRead($REGKEY_CONFIG, $REGKEY_TCTRL) = "1"
EndFunc
Func _setCtrl()
   RegWrite($REGKEY_CONFIG, $REGKEY_TCTRL, "REG_SZ", "1");
EndFunc
Func _unsetCtrl()
   RegWrite($REGKEY_CONFIG, $REGKEY_TCTRL, "REG_SZ", "0");
EndFunc

Func _getSensitivity()
   $sval = Number(RegRead($REGKEY_CONFIG, $REGKEY_SENSIT))
   If $sval < 1 Then
     $sval = 2
   EndIf
   Return $sval
EndFunc
Func _setSensitivity($sval)
  If $sval = 0 Then
    $sval = _getSensitivity()
  Else
    RegWrite($REGKEY_CONFIG, $REGKEY_SENSIT, "REG_DWORD", $sval);
  EndIf

  $needed_shake_count = $sval;

  Local const $sname = _sensitivityToName($sval);
  TrayItemSetState($idSensit0, _trayChecked($sname = "High"))
  TrayItemSetState($idSensit1, _trayChecked($sname = "Medium"))
  TrayItemSetState($idSensit2, _trayChecked($sname = "Low"))
EndFunc
Func _sensitivityToName($sval)
  If $sval <= $SENSITIVITY_HIGH Then
    Return "High"
  ElseIf $sval = $SENSITIVITY_MEDIUM Then
    Return "Medium"
  Else
    Return "Low"
  EndIf
EndFunc

Func _trayChecked($set)
  If $set Then
    Return $TRAY_CHECKED
  EndIf
  Return $TRAY_UNCHECKED
EndFunc

Func _isCtrlPressed()
  Return _IsPressed("A2") Or _IsPressed("A3")
EndFunc

Func _Quit()
   _GDIPlus_ShutDown()
   Exit
EndFunc   ;==>_Quit

Func SetBitmap($hGUI, $hImage, $iOpacity)
   Local $hScrDC, $hMemDC, $hBitmap, $hOld, $pSize, $tSize, $pSource, $tSource, $pBlend, $tBlend

   $hScrDC = _WinAPI_GetDC(0)
   $hMemDC = _WinAPI_CreateCompatibleDC($hScrDC)
   $hBitmap = _GDIPlus_BitmapCreateHBITMAPFromBitmap($hImage)
   $hOld = _WinAPI_SelectObject($hMemDC, $hBitmap)
   $tSize = DllStructCreate($tagSIZE)
   $pSize = DllStructGetPtr($tSize)
   DllStructSetData($tSize, "X", _GDIPlus_ImageGetWidth($hImage))
   DllStructSetData($tSize, "Y", _GDIPlus_ImageGetHeight($hImage))
   $tSource = DllStructCreate($tagPOINT)
   $pSource = DllStructGetPtr($tSource)
   $tBlend = DllStructCreate($tagBLENDFUNCTION)
   $pBlend = DllStructGetPtr($tBlend)
   DllStructSetData($tBlend, "Alpha", $iOpacity)
   DllStructSetData($tBlend, "Format", $AC_SRC_ALPHA)
   _WinAPI_UpdateLayeredWindow($hGUI, $hScrDC, 0, $pSize, $hMemDC, $pSource, 0, $pBlend, $ULW_ALPHA)
   _WinAPI_ReleaseDC(0, $hScrDC)
   _WinAPI_SelectObject($hMemDC, $hOld)
   _WinAPI_DeleteObject($hBitmap)
   _WinAPI_DeleteDC($hMemDC)
EndFunc   ;==>SetBitmap

; https://www.autoitscript.com/forum/topic/134350-file-to-base64-string-code-generator-v120-build-2015-01-20-embed-your-files-easily/
Func _WinAPI_TraySetHIcon($hIcon) ;function by Mat
    Local Const $tagNOTIFYICONDATA = _
                    "dword Size;" & _
                    "hwnd Wnd;" & _
                    "uint ID;" & _
                    "uint Flags;" & _
                    "uint CallbackMessage;" & _
                    "ptr Icon;" & _
                    "wchar Tip[128];" & _
                    "dword State;" & _
                    "dword StateMask;" & _
                    "wchar Info[256];" & _
                    "uint Timeout;" & _
                    "wchar InfoTitle[64];" & _
                    "dword InfoFlags;" & _
                    "dword Data1;word Data2;word Data3;byte Data4[8];" & _
                    "ptr BalloonIcon"
    Local Const $TRAY_ICON_GUI = WinGetHandle(AutoItWinGetTitle()), $NIM_ADD = 0, $NIM_MODIFY = 1, $NIF_MESSAGE = 1, $NIF_ICON = 2, $AUT_WM_NOTIFYICON = $WM_USER + 1, $AUT_NOTIFY_ICON_ID = 1
    Local $tNOTIFY = DllStructCreate($tagNOTIFYICONDATA)
    DllStructSetData($tNOTIFY, "Size", DllStructGetSize($tNOTIFY))
    DllStructSetData($tNOTIFY, "Wnd", $TRAY_ICON_GUI)
    DllStructSetData($tNOTIFY, "ID", $AUT_NOTIFY_ICON_ID)
    DllStructSetData($tNOTIFY, "Icon", $hIcon)
    DllStructSetData($tNOTIFY, "Flags", BitOR($NIF_ICON, $NIF_MESSAGE))
    DllStructSetData($tNOTIFY, "CallbackMessage", $AUT_WM_NOTIFYICON)
    Local $aRet = DllCall("shell32.dll", "int", "Shell_NotifyIconW", "dword", $NIM_MODIFY, "ptr", DllStructGetPtr($tNOTIFY))
    If (@error) Then Return SetError(1, 0, 0)
    Return $aRet[0] <> 0
EndFunc   ;==>_Tray_SetHIcon
Func _AutoIt_Icon($bSaveBinary = False, $sSavePath = @ScriptDir)
    Local $AutoIt_Icon
   $AutoIt_Icon &= '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'
   $AutoIt_Icon &= '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'
   $AutoIt_Icon &= 'UKFCUFyyWAZmzpzJXgZu3rwpGjZsqPo7yCoxrIjDCFhSA8DaR3UtevXeu3cvKN+JZQBLCXcZwU4A7mFFdzKSCmJCPmAWhN8aAG9cQkKCKF26dLCDMkKqcrFy5UohlxaWFjh9+rR4+eWXVX/nz2Sjc4QsowHwhsrJp7lz51JKSgq3gRRCqj6TJqFZ0tPTtaxfDqKjo6l3796qH0ffuM6hGTXrgq0BEIodPHiwiIiI4L7Z2OCjPz967OT5+jy2dfv27WPbAmfOnBGRkZEq9wOP005J1pHl4QaWAJw/f14MHTpUlCxZkjv5MBCw/8b2C8V251Sui4uLE3l5eSwBePDggZC2gGZMKvwGkjnamT0JZkJZAJDI0bNnT9WBLT75OLvPE7WBlbZO5dratWuLb775hiUABQUFYv/+/Rxn1DqzJ8FMKAkA4vVvvPGGPwYdTHl01Sruf0dXjdu+roewTZs2jZ0xBK3Rr18/1Xu8VHg/jsTbCgOkuqYWX1+RYYNj2p5WLo1mPOmFn/P6XfXq1RPXrl1j2wLSiAx793Aw0FVhgPwhUq3G+/httFq7r/J9q1atYgsAhKZLly6c+61l9mSYARS+5ygOkuqbny2JVB1fHRhhE5xU+d6YmBhx5coVlgDAh5Camqr5FBTvGw2hLXM+QKgAVZypMECqxOQj8UJVnc4k3Tfg9XsrVqwoPvvsM7YWuH37NidvEI4hW7mHgwU0PMxVHCRvb9Bp4h+6hNj8KZXf6NWrF9szCHz88ceqPgt4tNhHkYYDoIqRrenzTXwGcd0/JNsS35BC+G65yu9UrlxZnDhxgi0Ap06d4riHkT1sSfewkWlMsIL/SnqDI1ZvtEIclRwt+RfSB5EDaA7U1E0gH7UP6NSBEnHUD3BaveN0UeQaKpaVo0FgFoWg1MtqgPGDhElMpk83bSGRtQH7oXGAv43uWkpbwujoaHH27Fm2FsA1VatWVV3KMki3jRyJBqQfivAdeR8kVNbMo+C1TB/m4zcD2hLCPTxmzBjVZeAuOdw97Gl3NkMyTfKPpK+NqIHfTLqhVI2Cu2XCGwcd7XOCWrVqJXJyclgCAPfwoUOHRM2aNVWFYCu5XVk0wCDC6YvYHlUn33v7QIAae5+GaKVKlURaWpo2qVwt0L9/f1UBuEh6uNhFCBEleZYUJggTiQnlIjMzU0hDUkUAYAdNMHtAnAaoXEQNfWqBsmXLiuPHj7MF4Pr166JHjx6qWgBl4ZaJD9iymoUJGJfXST+ytYy3DyILGVvC7t27s9rFoI4Q20lUIAnfBSto+IQTxblbWxcBAidw+HxDsSXMyspSevPz8/PFyZMnxfz58zmuYRi8TnjxLAcEknxuCeHehZvXm+Wfm5srjh49KhITE0WjRo04aWzQRliOHBccsgLgW/gdKUxU06ZNtUkuDtQq7N69W7z11ltCqn1/3NvIYhpp9kA4Gcgl8OkZhDG4Y8cO7W1HoOjcuXNi/fr1onXr1v4ksRQlXMHRZg+Ck4HkDISWfU7WkCFDNFsgKSlJNGvWzJ9s5adxMbnq31TAtJ9PeqDK62Qh4UMx6UN17Uc8xJF5AVYDwstoGRKsyVWZfCSIxpL79lsC0AI7KHQCcJz0HEkXFkJ3CjxbyRuxxMDhs4JMagDpwjsQdURXSZ87Aj8IIzNJsiW5Dh9LA/39UGASjElHO9jfS8aTg5M+7AbYAvNInzx/1TxS3+HX708Gn/HrwhigwSNSyOGh41j1UPPY0yPf0V3fbQ5ECAeQ3skbaVvPsgsgJNjLQ2BQ+GJkEkvI4Erv/wAvIeoP0LodrcFgvWOSkaf4J9JT135LerlX2OC/JoswZqmBxw8AAAAASUVORK5CYII='
   Local $bString = Binary(_WinAPI_Base64Decode($AutoIt_Icon))
    If $bSaveBinary Then
        Local $hFile = FileOpen($sSavePath & "\AutoIt.ico", 18)
        FileWrite($hFile, $bString)
        FileClose($hFile)
    EndIf
    Return  $bString
 EndFunc   ;==>_AutoIt_Icon


;Code below was generated by: 'File to Base64 String' Code Generator v1.19 Build 2014-11-14
Func _Torus($bSaveBinary = False, $sSavePath = @ScriptDir)
   local $Pointer
   $Pointer &= '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'
   $Pointer &= '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'
   $Pointer &= '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'
   $Pointer &= 'r12UQ1fZuiUkJFhFRUXKDYKUWEiNpaDvtN1VspzREP76N/GeR90mW0euKW9mZqaqXy5lmQyDob7QPgUNKE9I+dOEuR3DZOuJ7XoOCgsL7RFKQT/+xj1bXE57UjBdLEM7yJ0zqNVUtAEzDw6eeeYZFX2JJLnaUljdKLRfQSP8hR3Zei62YZpsnYcNG8ZiEMTCIiZWQZ9qTWEVT87VVLKNwALYJHLf7RipCmXqjh3qAwcOsJhk4sSJKgxS4HKfBmSo0P+GUHls7y4hvdHZC0Ko92WaOnUqi0EU3iDhiRRWCCzCSudSof8rp7LYL0Cc6PPkjbD9RJJ8AHihxIslB4pukMjV3cmlgVnwIoszpNhYm0BOyEB3oUa6KxcADMNSDwHXjXCg6AYJBEtpWX6PFKTjXTp37sxiEKDoBon/0d3J4QymvEiXKPUQCgoKWAySl5enwiA7dXdyuIOlaamHgO16DhTeIOHJHGfhQgOSnPJixrF//34Wk+AdR6Zul6QtJDFSmEeSD2Hy5MksBlF0g8QY3R0c7iB5PqbhIT8EZBDCUQYOyrpeLQhN0N3BkQAu1ZV6EFlZWUqNgXjVcePGWbGxsbIGGa+7cyMBrApLPQi8UOLFUgb8eyTgxYVHClOADtfduZEAFvmQSVDqYeDhhgLScGVnZ6uatZSWJ5bcIwEcmJV6GHfddVdQxjh48KCVkZGhKg4kkHBGWUsAUSSCeE4c15Sa8lbmdu/t27dbKSkpqhLblSdth6oiFVz9IPVQyrrdG3lgV6xYYfXo0YPbFP5Scv2V4Wew2ah0ynvy5EnrpZdeslq2bOmmMSDkR/FcjvdIAMOy1MPBRQRfffWVlZaWZtWrV89tY/g0SXdHRioDSfLhIJuSoqCfUIWzTObllAmEQEpPeTUK2ZY6cXdStHwRYY/n764NALIg4GjHZt0ViXSQQRAX5OkeDYIRdqVDzghlCB5ksNP90CsrfCX+QneHVTVakxOBr/vhl6cz5CTVNdNZTeSRfhMEEtY4YIxrdHdQVeeXJLlwpli7hHA7UU3dHWP4GeRj1WkKGBQX6vQnjWduDWXTUOhr0rOekUneOGhmqAAkn8EDc8MY3wpNJSeg2hBG9CbJcIAK9DdysjlW191QQ+ggPfl+UmcKrHwuIw9dVmiQB9mWcH+rzBrJCaFZQs11N8bAx01Ci8gJ66usMf4p9KhQXd2Vl8VMpyoPLjPqR87mHs7YYPEKeVkxwhwR2iv0V6H1Qtt1V1YV/w+V6dhMlGdVywAAAABJRU5ErkJggg=='

    Local $bString = Binary(_WinAPI_Base64Decode($Pointer))
    If $bSaveBinary Then
        Local $hFile = FileOpen($sSavePath & "\Pointer.png", 18)
        FileWrite($hFile, $bString)
        FileClose($hFile)
    EndIf
    Return  $bString
EndFunc   ;==>_Torus
Func _WinAPI_Base64Decode($sB64String)
    Local $aCrypt = DllCall("Crypt32.dll", "bool", "CryptStringToBinaryA", "str", $sB64String, "dword", 0, "dword", 1, "ptr", 0, "dword*", 0, "ptr", 0, "ptr", 0)
    If @error Or Not $aCrypt[0] Then Return SetError(1, 0, "")
    Local $bBuffer = DllStructCreate("byte[" & $aCrypt[5] & "]")
    $aCrypt = DllCall("Crypt32.dll", "bool", "CryptStringToBinaryA", "str", $sB64String, "dword", 0, "dword", 1, "struct*", $bBuffer, "dword*", $aCrypt[5], "ptr", 0, "ptr", 0)
    If @error Or Not $aCrypt[0] Then Return SetError(2, 0, "")
    Return DllStructGetData($bBuffer, 1)
 EndFunc   ;==>_WinAPI_Base64Decode
