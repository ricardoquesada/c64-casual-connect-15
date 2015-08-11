# Makefile copied from Zoo Mania game

.SILENT:

IMAGE = "cc15_dist.d64"
C1541 = c1541
X64 = x64

all: disk

SRC=src/intro.s src/utils.s
prg:
	cl65 -d -g -Ln cc15.sym -u __EXEHDR__ -t c64 -o cc15.prg -C cc15.cfg ${SRC}

disk: prg
	$(C1541) -format "cc15,rq" d64 cc15.d64
	$(C1541) cc15.d64 -write cc15.prg
	$(C1541) cc15.d64 -list

dist: prg
	exomizer sfx sys -o cc15_exo.prg cc15.prg
	$(C1541) -format "cc15 dist,rq" d64 $(IMAGE)
	$(C1541) $(IMAGE) -write cc15_exo.prg "the race"
	$(C1541) $(IMAGE) -list

test: disk
	$(X64) -moncommands cc15.sym cc15.d64

testdist: dist
	$(X64) -moncommands cc15.sym $(IMAGE)

clean:
	rm -f src/*.o cc15.prg cc15_exo.prg cc15.d64 cc15.sym $(IMAGE)
