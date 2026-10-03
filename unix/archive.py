"""Portable archive operations for account transfer, including paths with spaces."""
import os
import pathlib
import stat
import sys
import tarfile
import zipfile


def extract(archive, destination):
    root = pathlib.Path(destination).resolve()

    def validate(name):
        target = (root / name.replace('\\', '/')).resolve()
        if target != root and root not in target.parents:
            raise ValueError('Archive contains an unsafe path')

    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as z:
            for item in z.infolist():
                validate(item.filename)
                if stat.S_ISLNK(item.external_attr >> 16):
                    raise ValueError('Archive contains a symbolic link')
            for item in z.infolist():
                # Windows PowerShell 5.1 writes backslash separators.
                item.filename = item.filename.replace('\\', '/')
                z.extract(item, root)
    else:
        with tarfile.open(archive) as t:
            for item in t.getmembers():
                validate(item.name)
                if not (item.isfile() or item.isdir()):
                    raise ValueError('Archive contains an unsupported entry')
            t.extractall(root)


def create(source, archive):
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for directory, dirs, files in os.walk(source):
            for name in dirs + files:
                item = os.path.join(directory, name)
                if os.path.islink(item):
                    continue
                z.write(item, os.path.relpath(item, source))


if __name__ == '__main__':
    try:
        if sys.argv[1] == 'create':
            create(sys.argv[2], sys.argv[3])
        elif sys.argv[1] == 'extract':
            extract(sys.argv[2], sys.argv[3])
        else:
            raise ValueError('Unknown archive operation')
    except Exception as error:
        print('Archive operation failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
