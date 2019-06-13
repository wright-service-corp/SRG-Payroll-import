BINLIB=wsc40t
SHELL=/QOpenSys/usr/bin/qsh
LIBL=WSC40T WTSLIB332 RJSEXPORT GACLIENT

all: ecprxmlcl.clle
# new stuff
%.clle: 
	-system -q "CRTSRCPF FILE($(BINLIB)/QCLLESRC) RCDLEN(112)"
	system "CPYFRMSTMF FROMSTMF('./source/$*.clle') TOMBR('/QSYS.lib/$(BINLIB).lib/QCLLESRC.file/$*.mbr') MBROPT(*replace)"
	liblist -a $(LIBL); system "CRTBNDCL PGM($(BINLIB)/$*) SRCFILE($(BINLIB)/QCLLESRC)"