#!/usr/bin/env python3
"""Configure identifiers in this extracted friend copy; never logs in or signs."""
import argparse,json,re,subprocess,sys
from pathlib import Path

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--namespace',required=True,help='A unique reverse-domain ID, e.g. com.xiaoming.lianaikeyboard2026')
    args=parser.parse_args();ns=args.namespace
    if not re.fullmatch(r'[a-zA-Z][a-zA-Z0-9]*(?:\.[a-zA-Z][a-zA-Z0-9]*){2,}',ns) or len(ns)>180 or ns=='com.lianai.keyboard.ios':
        parser.error('Choose your own unique reverse-domain namespace, e.g. com.xiaoming.lianaikeyboard2026')
    root=Path(__file__).resolve().parent.parent
    record=root/'config/FriendNamespace.json'
    old=json.loads(record.read_text()) if record.exists() else {'namespace':'com.lianai.keyboard.ios','group':'group.com.lianai.keyboard','shared':'com.lianai.keyboard.shared'}
    new={'namespace':ns,'group':'group.'+ns,'shared':ns+'.shared'}
    files={'scripts/generate_project.py':[(old['namespace'],ns)],
      'Packages/LianAiCore/Sources/LianAiCore/Models.swift':[(old['group'],new['group'])]}
    for folder in ['App','Keyboard']:
        files[folder+'/LianAi.entitlements']=[(old['group'],new['group']),(old['shared'],new['shared'])]
        files[folder+'/Info.plist']=[(old['shared'],new['shared'])]
    for folder in ['Tests','UITests']:
        for path in (root/folder).glob('*.swift'):
            files[str(path.relative_to(root))]=[(old['namespace'],ns)]
    for relative,replacements in files.items():
        path=root/relative;data=path.read_text()
        for before,after in replacements:data=data.replace(before,after)
        path.write_text(data)
    record.write_text(json.dumps(new,indent=2)+'\n')
    subprocess.run([sys.executable,str(root/'scripts/generate_project.py')],cwd=root,check=True)
    print('Main App:',ns)
    print('Keyboard:',ns+'.Keyboard')
    print('App Group:',new['group'])
    print('Shared Keychain: $(AppIdentifierPrefix)'+new['shared'])
    print('Open LianAiKeyboard.xcodeproj; select your own Personal Team for both targets in Xcode.')
if __name__=='__main__':main()
