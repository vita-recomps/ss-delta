"""Write ss-delta.ini from the default text in ss-delta/settings.cpp (DEFAULT_INI).

usage: python -I ssdelta_ini.py <settings.cpp> <out ini> [vita_fs]
With vita_fs, [paths] vita_fs is set to it.
"""
import sys


def main():
    src, out = sys.argv[1], sys.argv[2]
    vita_fs = sys.argv[3] if len(sys.argv) > 3 else ''
    text = open(src, encoding='utf-8').read().split('DEFAULT_INI = R"(', 1)[1].split(')";', 1)[0]
    if vita_fs:
        line = ';vita_fs = C:/Games/ss-delta/fs'
        assert line in text, 'default ini changed: update ssdelta_ini.py'
        text = text.replace(line, 'vita_fs = ' + vita_fs.replace('\\', '/'))
    open(out, 'w', encoding='utf-8', newline='\r\n').write(text)


if __name__ == '__main__':
    main()
