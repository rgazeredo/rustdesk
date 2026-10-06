"""Capture the actual Windows app; no compositing, masking or UI replacement."""
import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import win32api
import win32con
import win32gui
import win32process
from PIL import ImageGrab
from pywinauto import Desktop

ctypes.windll.user32.SetProcessDPIAware()
mode=win32api.EnumDisplaySettings(None,win32con.ENUM_CURRENT_SETTINGS)
mode.PelsWidth=1920
mode.PelsHeight=1080
result=win32api.ChangeDisplaySettings(mode,0)
if result!=0: raise RuntimeError(f'Display resize failed: {result}')
exe=Path('bundle/AZSign Remote.exe').resolve()
process=subprocess.Popen([str(exe)],cwd=exe.parent)
out=Path('store-screenshots')
try:
    handle=None
    for _ in range(60):
        found=[]
        def visit(hwnd,unused):
            _,pid=win32process.GetWindowThreadProcessId(hwnd)
            if pid==process.pid and win32gui.IsWindowVisible(hwnd) and win32gui.GetWindowText(hwnd): found.append(hwnd)
        win32gui.EnumWindows(visit,None)
        if found: handle=found[0];break
        time.sleep(.5)
    if not handle: raise RuntimeError('No application window')
    win32gui.ShowWindow(handle,win32con.SW_RESTORE)
    win32gui.SetWindowPos(handle,win32con.HWND_TOP,40,40,1600,900,win32con.SWP_SHOWWINDOW)
    try: win32gui.SetForegroundWindow(handle)
    except Exception: pass
    time.sleep(8)
    win32api.SetCursorPos((1850,1020))
    rect=win32gui.GetWindowRect(handle)
    ImageGrab.grab(bbox=rect).save(out/('01-entrada.png' if sys.argv[1]=='login' else '02-dispositivos.png'))
    if sys.argv[1]=='catalog':
        requests=(out/'requests.txt').read_text() if (out/'requests.txt').exists() else ''
        if 'GET /api/v1/desktop/address-book' not in requests: raise RuntimeError('Catalog fixture was not loaded; inspect screenshot and TLS diagnostics')
        window=Desktop(backend='uia').window(handle=handle)
        controls=window.descendants()
        (out/'controls.json').write_text(json.dumps([{'text':c.window_text(),'type':c.element_info.control_type,'rect':str(c.rectangle())} for c in controls],ensure_ascii=False,indent=2),encoding='utf-8')
        edits=[c for c in controls if c.element_info.control_type=='Edit']
        if len(edits)==1:
            edits[0].set_focus()
            edits[0].type_keys('Vitrine',with_spaces=True)
            time.sleep(2)
            win32api.SetCursorPos((1850,1020))
            if 'search=Vitrine' in (out/'requests.txt').read_text():
                ImageGrab.grab(bbox=win32gui.GetWindowRect(handle)).save(out/'03-busca.png')
finally:
    subprocess.run(['taskkill','/F','/T','/PID',str(process.pid)],capture_output=True)
