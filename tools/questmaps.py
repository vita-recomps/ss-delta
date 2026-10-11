# Prints one line per map in quest_param.csv: "<map id> <Stage Select index> <quest id> <quests on it>".
# The Stage Select index is the quest's row (from 0), which is how the debug menu counts them.
# Extract the table first (archive_patch3 overrides archive):
#   python -I tools/lspk.py extract <...>/retail/archive_patch3 build/lspk boot/quest_param.csv
#   python -I tools/questmaps.py build/lspk/resource/boot/quest_param.csv
import csv
import io
import sys


def main():
    with open(sys.argv[1], 'rb') as f:
        rows = list(csv.reader(io.StringIO(f.read().decode('cp932'))))
    col = rows[0].index('MAP(ID)')
    quests = [r for r in rows[1:] if len(r) > col and r[4]]
    first, count = {}, {}
    for i, r in enumerate(quests):
        count[r[col]] = count.get(r[col], 0) + 1
        first.setdefault(r[col], (i, r[4]))
    for m, (i, q) in first.items():
        if m:
            print(m, i, q, count[m])


if __name__ == '__main__':
    main()
