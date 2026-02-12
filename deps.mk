argparser.o: modules/argparser.c modules/argparser.h \
  modules/locale_macros.h
devio.o: modules/devio.c modules/devio.h \
  /opt/homebrew/Cellar/libusb/1.0.29/include/libusb-1.0/libusb.h \
  modules/locale_macros.h modules/rgbmodes.h modules/argparser.h \
  modules/qc2s_protocol.h
rgbmodes.o: modules/rgbmodes.c modules/rgbmodes.h modules/argparser.h \
  modules/locale_macros.h
