UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	OS = macos
else ifeq ($(UNAME_S),FreeBSD)
	OS = freebsd
else
	OS = linux
endif

VERSION = 1.0.5

CFLAGS_DEV = -g -Wall -DVERSION="\"$(VERSION)\"" -D DEBUG
CFLAGS_INS = -s -O2 -DVERSION="\"$(VERSION)\""
CPPFLAGS =
LDFLAGS =

LIBS = -lusb-1.0

SRCMODULES = modules/argparser.c modules/devio.c modules/rgbmodes.c
OBJMODULES = $(SRCMODULES:.c=.o)

BINPATH = ./quadcastrgb
DEVBINPATH = ./dev
MANPATH = man/quadcastrgb.1

BINDIR_INS = $${HOME}/.local/bin/
MANDIR_INS = $${HOME}/.local/share/man/man1/

# Packaging
DEBPKGVER = 2
DEBARCH = amd64
DEBNAME = quadcastrgb-$(VERSION)-$(DEBPKGVER)-$(DEBARCH)

# System-dependent part
ifeq ($(OS),freebsd)
	LIBS = -lusb-1.0 -lintl # libintl requires the explicit indication
endif
ifeq ($(OS),freebsd) # thus, gcc required on FreeBSD
	CC = gcc # clang seems to be unable to find libusb & libintl
endif
ifeq ($(OS),macos) # pass this info to the source code to disable daemonization
	CFLAGS_DEV += -D OS_MAC
	CFLAGS_INS += -D OS_MAC
	CPPFLAGS += $(shell pkg-config --cflags libusb-1.0 2>/dev/null | sed 's|/libusb-1.0$$||')
	LDFLAGS += $(shell pkg-config --libs-only-L libusb-1.0 2>/dev/null)
	HIDAPI_CFLAGS := $(shell pkg-config --cflags hidapi 2>/dev/null | sed 's|/hidapi$$||')
	HIDAPI_LIBS := $(shell pkg-config --libs hidapi 2>/dev/null)
	ifneq ($(strip $(HIDAPI_CFLAGS) $(HIDAPI_LIBS)),)
		CFLAGS_DEV += -DUSE_HIDAPI $(HIDAPI_CFLAGS)
		CFLAGS_INS += -DUSE_HIDAPI $(HIDAPI_CFLAGS)
		LIBS += $(HIDAPI_LIBS)
	endif
endif
# END

quadcastrgb: main.c $(OBJMODULES)
	$(CC) $(CPPFLAGS) $(CFLAGS_INS) $^ $(LDFLAGS) $(LIBS) -o $(BINPATH)

dev: main.c $(OBJMODULES)
	$(CC) $(CPPFLAGS) $(CFLAGS_DEV) $^ $(LDFLAGS) $(LIBS) -o $(DEVBINPATH)

# For directories
%/:
	mkdir -p $@
# For modules
%.o: %.c %.h
ifeq (quadcastrgb, $(MAKECMDGOALS))
	$(CC) $(CPPFLAGS) $(CFLAGS_INS) -c $< -o $@
else ifeq (install, $(MAKECMDGOALS))
	$(CC) $(CPPFLAGS) $(CFLAGS_INS) -c $< -o $@
else ifeq (debpkg, $(MAKECMDGOALS))
	$(CC) $(CPPFLAGS) $(CFLAGS_INS) -c $< -o $@
else ifeq (rpmpkg, $(MAKECMDGOALS))
	$(CC) $(CPPFLAGS) $(CFLAGS_INS) -c $< -o $@
else
	$(CC) $(CPPFLAGS) $(CFLAGS_DEV) -c $< -o $@
endif

.PHONY: dev quadcastrgb install debpkg rpmpkg tags clean test

install: quadcastrgb $(BINDIR_INS) $(MANDIR_INS)
	cp $(BINPATH) $(BINDIR_INS)
	cp $(MANPATH).gz $(MANDIR_INS)

debpkg: quadcastrgb
	mkdir -p packages/deb/$(DEBNAME)/DEBIAN \
		 packages/deb/$(DEBNAME)/usr/bin \
		 packages/deb/$(DEBNAME)/usr/share/man/man1
	cp packages/deb/control packages/deb/$(DEBNAME)/DEBIAN/control
	cp $(BINPATH) packages/deb/$(DEBNAME)/usr/bin/quadcastrgb
	cp $(MANPATH).gz packages/deb/$(DEBNAME)/usr/share/man/man1
	dpkg --build packages/deb/$(DEBNAME)

rpmpkg: main.c $(SRCMODULES) man/quadcastrgb.1.gz
	rpmdev-setuptree
	cp -r main.c Makefile modules man $${HOME}/rpmbuild/BUILD/
	cp packages/rpm/quadcastrgb.spec $${HOME}/rpmbuild/SPECS/
	tar -zcf $${HOME}/rpmbuild/SOURCES/quadcastrgb-${VERSION}.tgz .
	rpmbuild --ba $${HOME}/rpmbuild/SPECS/quadcastrgb.spec

ifneq (clean, $(MAKECMDGOALS))
-include deps.mk
endif

deps.mk: $(SRCMODULES)
	$(CC) $(CPPFLAGS) -MM $^ > $@

test: tests/test_qc2s.c
	$(CC) $(CPPFLAGS) -g -Wall -D DEBUG tests/test_qc2s.c -o tests/test_qc2s
	./tests/test_qc2s

tags:
	ctags *.c $(SRCMODULES)

clean:
	rm -rf $(OBJMODULES) $(BINPATH) $(DEVBINPATH) tests/test_qc2s tags \
		packages/deb/$(DEBNAME) deb/$(DEBNAME)
