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
import win32com.client
from PIL import ImageGrab

ctypes.windll.user32.SetProcessDPIAware()
print('Preparing display',flush=True)
mode=win32api.EnumDisplaySettings(None,win32con.ENUM_CURRENT_SETTINGS)
mode.PelsWidth=1920
mode.PelsHeight=1080
result=win32api.ChangeDisplaySettings(mode,0)
if result!=0: raise RuntimeError(f'Display resize failed: {result}')
exe=Path('bundle/AZSign Remote.exe').resolve()
process=subprocess.Popen([str(exe)],cwd=exe.parent)
print(f'Launched {process.pid}',flush=True)
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
    client=win32gui.GetClientRect(handle)
    win32gui.SetWindowPos(handle,win32con.HWND_TOP,40,40,1600+(1600-client[2]),900+(900-client[3]),win32con.SWP_SHOWWINDOW)
    try: win32gui.SetForegroundWindow(handle)
    except Exception: pass
    time.sleep(8)
    win32api.SetCursorPos((1850,1020))
    client=win32gui.GetClientRect(handle)
    origin=win32gui.ClientToScreen(handle,(0,0))
    rect=(*origin,origin[0]+client[2],origin[1]+client[3])
    ImageGrab.grab(bbox=rect).save(out/('01-entrada.png' if sys.argv[1]=='login' else '02-dispositivos.png'))
    print(f'Captured {sys.argv[1]} {rect}',flush=True)
    if sys.argv[1]=='catalog':
        requests=(out/'requests.txt').read_text() if (out/'requests.txt').exists() else ''
        if 'GET /api/v1/desktop/address-book' not in requests: raise RuntimeError('Catalog fixture was not loaded; inspect screenshot and TLS diagnostics')
        # Search field position verified against the first native catalog screenshot.
        win32api.SetCursorPos((origin[0]+300,origin[1]+196))
        win32api.mouse_event(win32con.MOUSEEVENTF_LEFTDOWN,0,0)
        win32api.mouse_event(win32con.MOUSEEVENTF_LEFTUP,0,0)
        time.sleep(.3)
        win32com.client.Dispatch('WScript.Shell').SendKeys('Vitrine')
        time.sleep(2)
        if 'search=Vitrine' not in (out/'requests.txt').read_text(): raise RuntimeError('Search did not reach fixture')
        win32api.SetCursorPos((1850,1020))
        ImageGrab.grab(bbox=rect).save(out/'03-busca.png')
finally:
    subprocess.run(['taskkill','/F','/T','/PID',str(process.pid)],capture_output=True)
