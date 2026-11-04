#!/usr/bin/env python3
"""Capture the local Android acceptance app through adb/UIAutomator (isolated emulator)."""
import argparse, hashlib, json, re, subprocess, time, xml.etree.ElementTree as ET
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--adb',required=True);p.add_argument('--serial',required=True);p.add_argument('--output',required=True);args=p.parse_args()
out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
def adb(*command, binary=False):
 return subprocess.check_output([args.adb,'-s',args.serial,*command],text=not binary)
def tree():
 adb('shell','uiautomator','dump','/sdcard/lianai-parity.xml')
 return ET.fromstring(adb('shell','cat','/sdcard/lianai-parity.xml'))
def click(text, scroll=False):
 for attempt in range(5 if scroll else 1):
  root=tree()
  for n in root.iter('node'):
   if n.get('text')==text or n.get('content-desc')==text:
    x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')))
    if y2>y1 and x2>x1:
     adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));return
  if scroll: adb('shell','input','swipe','620','2100','620','800','350')
 raise RuntimeError('Missing Android element: '+text)
def capture(name):
 root=tree()
 ET.ElementTree(root).write(out/(name+'.xml'),encoding='utf-8')
 (out/(name+'.png')).write_bytes(adb('exec-out','screencap','-p',binary=True))
 return [n.get('text') for n in root.iter('node') if n.get('text')]
try: click('稍后再说')
except RuntimeError: pass
click('首页');pages={'home':capture('home')}
for page,title in [('profile','我的'),('test','键盘')]:
 click(title);pages[page]=capture(page)
for page,title in [('subscription','订阅套餐'),('guide','使用指引'),('about','关于我们'),('settings','设置')]:
 click('我的');click(title,True);pages[page]=capture(page)
for page,title in [('layout','布局和显示'),('effects','按键效果'),('auxiliary','辅助输入'),('management','键盘管理'),('models','大模型配置'),('optimize','优化输入'),('clipboard','剪贴板'),('data','本机数据'),('permissions','权限管理')]:
 click('我的');click('设置',True);click(title,True);pages[page]=capture(page)
 if page in ['auxiliary','management','models','optimize','data']:
  adb('shell','input','swipe','620','2100','620','650','400');pages[page+'-scrolled']=capture(page+'-scrolled')
(out/'page-texts.json').write_text(json.dumps(pages,ensure_ascii=False,indent=2))
print(json.dumps({k:len(v) for k,v in pages.items()},ensure_ascii=False))
