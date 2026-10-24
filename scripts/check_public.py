#!/usr/bin/env python3
"""Scan publishable files without printing sensitive matched values."""
from pathlib import Path
import re,subprocess,hashlib
ROOT=Path(__file__).resolve().parents[1]
PATTERNS={
    'private-key':rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'github-token':rb'(?:ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})',
    'jwt':rb'eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}',
    'personal-path':rb'/Users/[A-Za-z0-9_.-]+/',
    'device-id':rb'(?:iot_cn_|miaomiaoc_cn_|zhimi_cn_)[A-Za-z0-9_]{8,}',
}
def main():
    names=subprocess.check_output(['git','ls-files','-z'],cwd=ROOT).decode().split('\0')
    problems=[];count=0
    for name in filter(None,names):
        path=ROOT/name
        if path.is_symlink():problems.append((name,'symlink'));continue
        data=path.read_bytes();count+=1
        for label,pattern in PATTERNS.items():
            if label=='personal-path' and name=='projects/mac-vitals/Vendor/macmon' and hashlib.sha256(data).hexdigest()=='57259ce6845d0904be247c8e860fcc923300bab52e28a01f476c22c852051286':continue
            if re.search(pattern,data):problems.append((name,label))
        if any(x in path.parts for x in ['备份','验证','__pycache__','交付']):problems.append((name,'excluded directory'))
    for name,label in problems:print(name+': '+label)
    print(f'Checked {count} public files; {len(problems)} findings')
    raise SystemExit(bool(problems))
if __name__=='__main__':main()
