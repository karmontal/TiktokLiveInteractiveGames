"""Pull single members out of a remote zip with HTTP range requests: remote_unzip.py URL OUT_DIR NAME..."""
import io
import os
import sys
import urllib.request
import zipfile


class RemoteFile(io.RawIOBase):
    def __init__(self, url):
        self.url = url
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req) as r:
            self.url = r.geturl()            # follow the redirect once, the signed link lasts an hour
            self.size = int(r.headers["Content-Length"])
        self.pos = 0

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        self.pos = {0: off, 1: self.pos + off, 2: self.size + off}[whence]
        return self.pos

    def readinto(self, b):
        if self.pos >= self.size:
            return 0
        end = min(self.size, self.pos + len(b)) - 1
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{end}"})
        with urllib.request.urlopen(req) as r:
            data = r.read()
        b[:len(data)] = data
        self.pos += len(data)
        return len(data)


url, out, names = sys.argv[1], sys.argv[2], sys.argv[3:]
z = zipfile.ZipFile(io.BufferedReader(RemoteFile(url), buffer_size=8 << 20))
if not names:
    for i in z.infolist():
        print(i.filename, i.file_size)
for n in names:
    target = os.path.join(out, os.path.basename(n))
    with z.open(n) as src, open(target, "wb") as dst:
        while chunk := src.read(8 << 20):
            dst.write(chunk)
    print("saved", target, os.path.getsize(target))
